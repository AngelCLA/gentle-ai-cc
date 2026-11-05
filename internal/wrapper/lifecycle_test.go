package wrapper_test

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

// Platform-tagged callers deliver a real native signal, not a test bypass.
func signalLifetime(t *testing.T, expectedCode int, configure func(*exec.Cmd), interrupt func(*os.Process) error) {
	f := setup(t)
	f.env = append(f.env, "FIXTURE_BARRIER=1", "FIXTURE_IGNORE_SIGNALS=1")
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	owner := f.command(ctx, "sync")
	configure(owner)
	// Real files do not turn Wait into an inherited-stdout-pipe wait.
	output, err := os.Create(filepath.Join(f.home, "output"))
	if err != nil {
		t.Fatal(err)
	}
	defer output.Close()
	owner.Stdout, owner.Stderr = output, output
	if err := owner.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() {
		_ = os.WriteFile(filepath.Join(f.home, "release"), nil, 0600)
		if owner.ProcessState == nil {
			_ = owner.Process.Kill()
			_ = owner.Wait()
		}
	}()
	waitFor(t, filepath.Join(f.home, "started"))
	before := f.read()
	if err := interrupt(owner.Process); err != nil {
		t.Fatal(err)
	}
	done := make(chan error, 1)
	go func() { done <- owner.Wait() }()
	select {
	case err := <-done:
		var exit *exec.ExitError
		if !errors.As(err, &exit) {
			t.Fatalf("signal should exit with status %d, got error %v", expectedCode, err)
		}
		if code := exit.ExitCode(); code != expectedCode {
			t.Fatalf("signal should exit with status %d, got %d", expectedCode, code)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("invoking process did not exit after signal")
	}
	check(t, f.run("install"), 1, "", busy)
	if before != f.read() {
		t.Fatal("cleanup ran before ignoring writer completed")
	}
	if err := os.WriteFile(filepath.Join(f.home, "release"), nil, 0600); err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if !strings.Contains(f.read(), "command-code") {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	check(t, f.run("sync"), 0, expected("sync"), "")
}

func TestMissingStateAndNoOfficialAgents(t *testing.T) {
	f := setup(t)
	fresh := t.TempDir()
	f.home, f.state = fresh, filepath.Join(fresh, ".gentle-ai", "state.json")
	f.env = append(f.env, "HOME="+fresh, "USERPROFILE="+fresh)
	check(t, f.run("sync-all"), 0, "No other agents recorded; skipping official sync.\nCompanion sync: command-code\nsync\n--agent\ncommand-code\n", "")
	if _, err := os.Stat(f.state); !os.IsNotExist(err) {
		t.Fatal("missing state was created", err)
	}
	if _, err := os.Stat(filepath.Join(filepath.Dir(f.state), "gentle-cc.lock")); err != nil {
		t.Fatal(err)
	}
}

func copyExecutable(t *testing.T, source, destination string) {
	t.Helper()
	data, err := os.ReadFile(source)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(destination, data, 0700); err != nil {
		t.Fatal(err)
	}
}

func TestBuildRouteWithNativeGoFixture(t *testing.T) {
	f := setup(t)
	repo := filepath.Join(f.home, "repo")
	if err := os.Mkdir(repo, 0700); err != nil {
		t.Fatal(err)
	}
	name := "go"
	if runtime.GOOS == "windows" {
		name += ".exe"
	}
	copyExecutable(t, child, filepath.Join(f.home, name))
	f.env = append(f.env, "GENTLE_CC_REPO="+repo)
	check(t, f.run("build", "--agent=pi"), 0,
		"Building companion from "+repo+" ...\nbuild\n-o\n"+child+"\n./cmd/gentle-ai\nBuilt "+child+"\n", "")
}

func TestWindowsSiblingCompanionDefault(t *testing.T) {
	if runtime.GOOS != "windows" {
		t.Skip("Windows sibling default")
	}
	f := setup(t)
	installed := filepath.Join(f.home, "gentle-cc.exe")
	copyExecutable(t, binary, installed)
	copyExecutable(t, child, filepath.Join(f.home, "gentle-ai-cc.exe"))
	f.env = append(f.env, "GENTLE_CC_BIN=")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, installed, "sync")
	cmd.Env = f.env
	output, err := cmd.CombinedOutput()
	if err != nil || string(output) != expected("sync") {
		t.Fatalf("%v: %s", err, output)
	}
}

func TestPostChildStateIsCleaned(t *testing.T) {
	f := setup(t)
	f.env = append(f.env, `FIXTURE_STATE={"installed_agents":["commandcode","claude-code"], "other": 987654321012345678901234567890}`)
	check(t, f.run("install"), 0, expected("install"), "")
	if f.read() != `{"installed_agents":["claude-code"], "other": 987654321012345678901234567890}` {
		t.Fatal("cleanup used preflight snapshot", f.read())
	}
}
