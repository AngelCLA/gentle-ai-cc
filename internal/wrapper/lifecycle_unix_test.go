//go:build linux || darwin

package wrapper_test

import (
	"os"
	"os/exec"
	"syscall"
	"testing"
)

func openOldState(path string) (*os.File, error) { return os.Open(path) }

func TestUnixTermKeepsLockForIgnoringWriter(t *testing.T) {
	signalLifetime(t, 143, func(*exec.Cmd) {}, func(process *os.Process) error {
		return process.Signal(syscall.SIGTERM)
	})
}
