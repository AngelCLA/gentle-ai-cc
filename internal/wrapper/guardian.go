package wrapper

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"strconv"
	"sync"
	"syscall"
)

// The only internal entry is an inherited anonymous pipe, not environment state
// or a trusted command-line operation. Even a forged pipe cannot skip any public
// guard: the receiver reruns routing validation and independently acquires the
// OS lock before reading shared state or starting a writer.
const guardianVersion = 1

type request struct {
	Version int      `json:"version"`
	Args    []string `json:"args"`
}

type operationSignals struct {
	mu    sync.Mutex
	child *exec.Cmd
	code  int
}

func (s *operationSignals) stopped() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.code
}

func (s *operationSignals) stop(sig os.Signal) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if sig == os.Interrupt {
		s.code = 130
	} else {
		s.code = 143
	}
	if s.child != nil {
		interruptProcess(s.child.Process, sig)
	}
}

func run(cmd *exec.Cmd, signals *operationSignals) int {
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	if signals != nil {
		configureWriter(cmd)
		signals.mu.Lock()
		if signals.code != 0 {
			code := signals.code
			signals.mu.Unlock()
			return code
		}
	}
	err := cmd.Start()
	if signals != nil {
		if err == nil {
			signals.child = cmd
		}
		signals.mu.Unlock()
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "gentle-cc: cannot start "+cmd.Path+": "+err.Error())
		if os.IsNotExist(err) {
			return 127
		}
		return 126
	}
	err = cmd.Wait()
	if signals != nil {
		signals.mu.Lock()
		signals.child = nil
		code := signals.code
		signals.mu.Unlock()
		if code != 0 {
			return code
		}
	}
	if err == nil {
		return 0
	}
	if exit, ok := err.(*exec.ExitError); ok {
		return processExitCode(exit)
	}
	return errorExit(err.Error())
}

func supervise(args []string) int {
	if err := platformAvailable(); err != nil {
		return errorExit(err.Error())
	}
	executable, err := os.Executable()
	if err != nil {
		return errorExit(err.Error())
	}
	reader, writer, err := os.Pipe()
	if err != nil {
		return errorExit("cannot start locked operation; no mutation started")
	}
	defer reader.Close()
	defer writer.Close()
	cmd := exec.Command(executable)
	if err := configureGuardian(cmd, reader); err != nil {
		return errorExit(err.Error())
	}
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	// Subscribe before Start so interrupt cannot leave an unobserved writer.
	signals := make(chan os.Signal, 4)
	signal.Notify(signals, os.Interrupt, syscall.SIGTERM)
	defer signal.Stop(signals)
	if err := cmd.Start(); err != nil {
		return errorExit("cannot start locked operation; no mutation started")
	}
	reader.Close()
	encoder := json.NewEncoder(writer)
	if err := encoder.Encode(request{guardianVersion, args}); err != nil {
		// Closing the pipe prevents an unauthenticated/incomplete operation.
		writer.Close()
		_ = cmd.Wait()
		return errorExit("cannot initialize locked operation; no mutation started")
	}
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	select {
	case sig := <-signals:
		code, event := 143, "terminate"
		if sig == os.Interrupt {
			code, event = 130, "interrupt"
		}
		_ = encoder.Encode(event)
		// The guardian, not this process, owns the lock until the writer exits.
		return code
	case err := <-done:
		if err == nil {
			return 0
		}
		if exit, ok := err.(*exec.ExitError); ok {
			return processExitCode(exit)
		}
		return errorExit(err.Error())
	}
}

func guardianMain(args []string) int {
	if err := platformAvailable(); err != nil {
		return errorExit(err.Error())
	}
	if len(args) != 1 {
		return errorExit("invalid guardian protocol")
	}
	handle, err := strconv.ParseUint(args[0], 10, 64)
	if err != nil || handle <= 2 || uint64(uintptr(handle)) != handle {
		return errorExit("invalid guardian pipe")
	}
	pipe := os.NewFile(uintptr(handle), "guardian-pipe")
	if pipe == nil {
		return errorExit("invalid guardian pipe")
	}
	defer pipe.Close()
	info, err := pipe.Stat()
	if err != nil || info.Mode()&os.ModeNamedPipe == 0 {
		return errorExit("invalid guardian pipe")
	}
	// Bounded single-frame startup; EOF or extra fields are not an operation.
	reader := bufio.NewReaderSize(pipe, 64*1024)
	line, err := reader.ReadSlice('\n')
	if err != nil {
		return errorExit("invalid guardian protocol")
	}
	var req request
	dec := json.NewDecoder(bytes.NewReader(line))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&req); err != nil || req.Version != guardianVersion || len(req.Args) == 0 || !protected(req.Args[0]) {
		return errorExit("invalid guardian operation")
	}
	if err := dec.Decode(new(any)); err != io.EOF {
		return errorExit("invalid guardian protocol")
	}
	if err := guard(req.Args); err != nil {
		return errorExit(err.Error())
	}
	if informational(req.Args[0], req.Args[1:]) {
		return errorExit("invalid guardian operation")
	}
	cfg, err := configuration()
	if err != nil {
		return errorExit(err.Error())
	}
	pending := &operationSignals{}
	signals := make(chan os.Signal, 4)
	signal.Notify(signals, os.Interrupt, syscall.SIGTERM)
	defer signal.Stop(signals)
	go func() {
		for sig := range signals {
			pending.stop(sig)
		}
	}()
	go func() {
		for {
			frame, err := reader.ReadSlice('\n')
			if err != nil {
				// Parent death is NOT cancellation: finish under the lock.
				return
			}
			var event string
			if json.Unmarshal(frame, &event) != nil {
				continue
			}
			switch event {
			case "interrupt":
				pending.stop(os.Interrupt)
			case "terminate":
				pending.stop(syscall.SIGTERM)
			}
		}
	}()
	lock, err := acquireLock(cfg.home)
	if err != nil {
		return errorExit(err.Error())
	}
	// Never explicitly unlock or unlink; closing the native owner is the only
	// release, after every child Wait and any cleanup/validation has finished.
	defer lock.Close()
	if pending.stopped() != 0 {
		return pending.stopped()
	}
	if _, err := readState(cfg.home); err != nil {
		return stateError(err)
	}
	return cfg.operation(req.Args, pending, true)
}
