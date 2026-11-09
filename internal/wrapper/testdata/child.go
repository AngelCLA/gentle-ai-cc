// A native public-CLI fixture; never invokes a shell or an installed companion.
package main

import (
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"syscall"
	"time"
)

func main() {
	home := os.Getenv("HOME")
	if os.Getenv("FIXTURE_IGNORE_SIGNALS") != "" {
		signal.Ignore(os.Interrupt, syscall.SIGTERM)
	}
	if os.Getenv("FIXTURE_BARRIER") != "" {
		if err := os.WriteFile(filepath.Join(home, "started"), []byte("started"), 0600); err != nil {
			os.Exit(95)
		}
		deadline := time.Now().Add(15 * time.Second)
		for {
			if _, err := os.Stat(filepath.Join(home, "release")); err == nil {
				break
			}
			if time.Now().After(deadline) {
				os.Exit(98)
			}
			time.Sleep(10 * time.Millisecond)
		}
	}
	for _, arg := range os.Args[1:] {
		fmt.Println(arg)
	}
	file, err := os.OpenFile(filepath.Join(home, "called"), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0600)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(97)
	}
	fmt.Fprintln(file, filepath.Base(os.Args[0]))
	file.Close()
	companion := len(os.Args) > 3 && os.Args[2] == "--agent" && os.Args[3] == "command-code"
	value := os.Getenv("FIXTURE_STATE")
	if companion && os.Getenv("FIXTURE_COMPANION_STATE") != "" {
		value = os.Getenv("FIXTURE_COMPANION_STATE")
	}
	if value != "" {
		if err := os.WriteFile(filepath.Join(home, ".gentle-ai", "state.json"), []byte(value), 0600); err != nil {
			os.Exit(96)
		}
	}
	code, _ := strconv.Atoi(os.Getenv("FIXTURE_EXIT"))
	if companion && os.Getenv("FIXTURE_COMPANION_EXIT") != "" {
		code, _ = strconv.Atoi(os.Getenv("FIXTURE_COMPANION_EXIT"))
	}
	os.Exit(code)
}
