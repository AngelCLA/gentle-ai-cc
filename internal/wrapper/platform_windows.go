//go:build windows

package wrapper

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"syscall"
	"unsafe"
)

var (
	kernel32                 = syscall.NewLazyDLL("kernel32.dll")
	lockFileEx               = kernel32.NewProc("LockFileEx")
	replaceFileW             = kernel32.NewProc("ReplaceFileW")
	generateConsoleCtrlEvent = kernel32.NewProc("GenerateConsoleCtrlEvent")
)

func platformAvailable() error { return nil }

func acquireLock(home string) (*os.File, error) {
	dir := filepath.Join(home, ".gentle-ai")
	if err := os.MkdirAll(dir, 0700); err != nil {
		return nil, fmt.Errorf("cannot acquire shared-state OS lock; no mutation started")
	}
	wideDir, err := syscall.UTF16PtrFromString(dir)
	if err != nil {
		return nil, err
	}
	attrs, err := syscall.GetFileAttributes(wideDir)
	if err != nil || attrs&syscall.FILE_ATTRIBUTE_REPARSE_POINT != 0 {
		return nil, fmt.Errorf("cannot acquire shared-state OS lock; unsafe state directory")
	}
	name, err := syscall.UTF16PtrFromString(filepath.Join(dir, "gentle-cc.lock"))
	if err != nil {
		return nil, err
	}
	// No DELETE sharing: the persistent lock cannot be renamed/unlinked while
	// owned. OPEN_REPARSE_POINT opens a link itself, never its target.
	handle, err := syscall.CreateFile(name, syscall.GENERIC_READ|syscall.GENERIC_WRITE,
		syscall.FILE_SHARE_READ|syscall.FILE_SHARE_WRITE, nil, syscall.OPEN_ALWAYS,
		syscall.FILE_ATTRIBUTE_NORMAL|syscall.FILE_FLAG_OPEN_REPARSE_POINT, 0)
	if err != nil {
		if err == syscall.ERROR_ACCESS_DENIED || err == syscall.Errno(32) {
			return nil, fmt.Errorf("%s", busyError)
		}
		return nil, fmt.Errorf("cannot acquire shared-state OS lock; no mutation started")
	}
	file := os.NewFile(uintptr(handle), "gentle-cc.lock")
	var info syscall.ByHandleFileInformation
	err = syscall.GetFileInformationByHandle(handle, &info)
	kind, typeErr := syscall.GetFileType(handle)
	if err != nil || typeErr != nil || kind != syscall.FILE_TYPE_DISK ||
		info.FileAttributes&(syscall.FILE_ATTRIBUTE_DIRECTORY|syscall.FILE_ATTRIBUTE_REPARSE_POINT) != 0 || info.NumberOfLinks != 1 {
		file.Close()
		return nil, fmt.Errorf("cannot acquire shared-state lock; lock must be a regular single-link file")
	}
	var overlapped syscall.Overlapped
	// LOCKFILE_FAIL_IMMEDIATELY | LOCKFILE_EXCLUSIVE_LOCK; byte zero is enough
	// to coordinate all wrappers, including those opening a different handle.
	ok, _, callErr := lockFileEx.Call(uintptr(handle), 3, 0, 1, 0, uintptr(unsafe.Pointer(&overlapped)))
	if ok == 0 {
		file.Close()
		if callErr == syscall.Errno(33) || callErr == syscall.ERROR_IO_PENDING {
			return nil, fmt.Errorf("%s", busyError)
		}
		return nil, fmt.Errorf("cannot acquire shared-state OS lock; no mutation started")
	}
	return file, nil
}

func replaceFile(source, destination string) error {
	from, err := syscall.UTF16PtrFromString(source)
	if err != nil {
		return err
	}
	to, err := syscall.UTF16PtrFromString(destination)
	if err != nil {
		return err
	}
	// Cleanup always replaces an existing state file. ReplaceFileW supports
	// old readers that grant FILE_SHARE_DELETE; MoveFileExW with replacement
	// can fail with ERROR_ACCESS_DENIED even for those compatible handles.
	// The same-directory source is already flushed and closed. Do not ignore
	// ACL merge errors, create a backup, or fall back to copy/delete.
	ok, _, callErr := replaceFileW.Call(uintptr(unsafe.Pointer(to)), uintptr(unsafe.Pointer(from)), 0, 0, 0, 0)
	if ok == 0 {
		return callErr
	}
	return nil
}

func configureGuardian(cmd *exec.Cmd, reader *os.File) error {
	handle := syscall.Handle(reader.Fd())
	if err := syscall.SetHandleInformation(handle, syscall.HANDLE_FLAG_INHERIT, syscall.HANDLE_FLAG_INHERIT); err != nil {
		return err
	}
	cmd.Args = append(cmd.Args, "--gentle-cc-guardian", strconv.FormatUint(uint64(handle), 10))
	cmd.SysProcAttr = &syscall.SysProcAttr{
		CreationFlags:              syscall.CREATE_NEW_PROCESS_GROUP,
		AdditionalInheritedHandles: []syscall.Handle{handle},
	}
	return nil
}

func configureWriter(cmd *exec.Cmd) {
	cmd.SysProcAttr = &syscall.SysProcAttr{CreationFlags: syscall.CREATE_NEW_PROCESS_GROUP}
}

func interruptProcess(process *os.Process, _ os.Signal) {
	// CTRL_BREAK_EVENT targets the writer's own group. Never use TerminateProcess:
	// a signal-ignoring writer must finish before its guardian releases the lock.
	_, _, _ = generateConsoleCtrlEvent.Call(1, uintptr(process.Pid))
}

func processExitCode(exit *exec.ExitError) int { return exit.ExitCode() }
