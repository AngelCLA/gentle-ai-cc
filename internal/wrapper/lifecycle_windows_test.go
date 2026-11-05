//go:build windows

package wrapper_test

import (
	"os"
	"os/exec"
	"syscall"
	"testing"
)

// Old-reader replacement is possible only when the reader grants delete sharing.
func openOldState(path string) (*os.File, error) {
	name, err := syscall.UTF16PtrFromString(path)
	if err != nil {
		return nil, err
	}
	handle, err := syscall.CreateFile(name, syscall.GENERIC_READ,
		syscall.FILE_SHARE_READ|syscall.FILE_SHARE_WRITE|syscall.FILE_SHARE_DELETE,
		nil, syscall.OPEN_EXISTING, syscall.FILE_ATTRIBUTE_NORMAL, 0)
	if err != nil {
		return nil, err
	}
	return os.NewFile(uintptr(handle), path), nil
}

func TestWindowsControlBreakKeepsLockForIgnoringWriter(t *testing.T) {
	console, _, _ := syscall.NewLazyDLL("kernel32.dll").NewProc("GetConsoleWindow").Call()
	if console == 0 {
		t.Skip("no Windows console attached: Control-Break delivery cannot be certified")
	}
	signalLifetime(t, func(cmd *exec.Cmd) {
		cmd.SysProcAttr = &syscall.SysProcAttr{CreationFlags: syscall.CREATE_NEW_PROCESS_GROUP}
	}, func(process *os.Process) error {
		ok, _, err := syscall.NewLazyDLL("kernel32.dll").NewProc("GenerateConsoleCtrlEvent").Call(1, uintptr(process.Pid))
		if ok == 0 {
			return err
		}
		return nil
	})
}
