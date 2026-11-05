//go:build linux || darwin

package wrapper

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"
)

func platformAvailable() error { return nil }

func acquireLock(home string) (*os.File, error) {
	dir := filepath.Join(home, ".gentle-ai")
	if err := os.MkdirAll(dir, 0700); err != nil {
		return nil, fmt.Errorf("cannot acquire shared-state OS lock; no mutation started")
	}
	info, err := os.Lstat(dir)
	if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return nil, fmt.Errorf("cannot acquire shared-state OS lock; unsafe state directory")
	}
	fd, err := syscall.Open(filepath.Join(dir, "gentle-cc.lock"), syscall.O_RDWR|syscall.O_CREAT|syscall.O_NOFOLLOW|syscall.O_CLOEXEC, 0600)
	if err != nil {
		if err == syscall.EISDIR || err == syscall.EACCES {
			return nil, fmt.Errorf("%s", busyError)
		}
		return nil, fmt.Errorf("cannot acquire shared-state OS lock; no mutation started")
	}
	file := os.NewFile(uintptr(fd), "gentle-cc.lock")
	var st syscall.Stat_t
	if err := syscall.Fstat(fd, &st); err != nil || st.Mode&syscall.S_IFMT != syscall.S_IFREG || st.Nlink != 1 {
		file.Close()
		return nil, fmt.Errorf("cannot acquire shared-state lock; lock must be a regular single-link file")
	}
	if err := syscall.Flock(fd, syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		file.Close()
		if err == syscall.EAGAIN || err == syscall.EACCES {
			return nil, fmt.Errorf("%s", busyError)
		}
		return nil, fmt.Errorf("cannot acquire shared-state OS lock; no mutation started")
	}
	return file, nil
}

func replaceFile(source, destination string) error {
	return os.Rename(source, destination)
}

func configureGuardian(cmd *exec.Cmd, reader *os.File) error {
	cmd.Args = append(cmd.Args, "--gentle-cc-guardian", "3")
	cmd.ExtraFiles = []*os.File{reader}
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	return nil
}

func configureWriter(cmd *exec.Cmd) {
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
}

func interruptProcess(process *os.Process, sig os.Signal) {
	if signal, ok := sig.(syscall.Signal); ok {
		_ = syscall.Kill(-process.Pid, signal)
	}
}

func processExitCode(exit *exec.ExitError) int {
	if status, ok := exit.Sys().(syscall.WaitStatus); ok && status.Signaled() {
		return 128 + int(status.Signal())
	}
	return exit.ExitCode()
}
