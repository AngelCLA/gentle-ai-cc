//go:build !windows && !linux && !darwin

package wrapper

import (
	"fmt"
	"os"
	"os/exec"
)

func platformAvailable() error {
	return fmt.Errorf("OS locking unavailable; supported platforms are Windows, Linux and macOS")
}
func acquireLock(string) (*os.File, error)        { return nil, platformAvailable() }
func replaceFile(string, string) error            { return platformAvailable() }
func configureGuardian(*exec.Cmd, *os.File) error { return platformAvailable() }
func configureWriter(*exec.Cmd)                   {}
func interruptProcess(*os.Process, os.Signal)     {}
func processExitCode(exit *exec.ExitError) int    { return exit.ExitCode() }
