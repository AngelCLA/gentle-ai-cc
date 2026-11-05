package wrapper_test

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

var binary, child string

func TestMain(m *testing.M) {
	scratch, err := os.MkdirTemp("", "gentle-cc-tests-")
	if err != nil {
		panic(err)
	}
	suffix := ""
	if runtime.GOOS == "windows" {
		suffix = ".exe"
	}
	binary = filepath.Join(scratch, "gentle-cc"+suffix)
	child = filepath.Join(scratch, "fixture"+suffix)
	code := func() int {
		for _, build := range []struct{ out, src string }{
			{child, "./testdata/child.go"},
			{binary, "../../cmd/gentle-cc"},
		} {
			ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
			cmd := exec.CommandContext(ctx, "go", "build", "-trimpath", "-buildvcs=false", "-o", build.out, build.src)
			cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
			err := cmd.Run()
			cancel()
			if err != nil {
				return 1
			}
		}
		return m.Run()
	}()
	os.RemoveAll(scratch)
	os.Exit(code)
}

type fixture struct {
	t           *testing.T
	home, state string
	env         []string
}

type result struct {
	code     int
	out, err string
}

func setup(t *testing.T) *fixture {
	t.Helper()
	home := t.TempDir()
	f := &fixture{t: t, home: home, state: filepath.Join(home, ".gentle-ai", "state.json")}
	if err := os.MkdirAll(filepath.Dir(f.state), 0700); err != nil {
		t.Fatal(err)
	}
	f.write(`{"installed_agents":["command-code","commandcode","pi","pi"], "other":9007199254740993123456789}`)
	// Do not inherit host configuration or interpreter/tool search paths.
	f.env = []string{
		"HOME=" + home, "USERPROFILE=" + home, "LOCALAPPDATA=" + home, "PATH=" + home,
		"GENTLE_CC_BIN=" + child, "GENTLE_AI_BIN=" + child,
		"GENTLE_CC_REPO=" + filepath.Join(home, "absent"),
	}
	if runtime.GOOS == "windows" {
		f.env = append(f.env, "SystemRoot="+os.Getenv("SystemRoot"))
	}
	return f
}

func (f *fixture) write(s string) {
	f.t.Helper()
	if err := os.WriteFile(f.state, []byte(s), 0600); err != nil {
		f.t.Fatal(err)
	}
}

func (f *fixture) read() string {
	f.t.Helper()
	data, err := os.ReadFile(f.state)
	if err != nil {
		f.t.Fatal(err)
	}
	return string(data)
}

func (f *fixture) command(ctx context.Context, args ...string) *exec.Cmd {
	cmd := exec.CommandContext(ctx, binary, args...)
	cmd.Env = f.env
	return cmd
}

func (f *fixture) run(args ...string) result {
	f.t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	cmd := f.command(ctx, args...)
	var out, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, &stderr
	err := cmd.Run()
	code := 0
	if err != nil {
		if exit, ok := err.(*exec.ExitError); ok {
			code = exit.ExitCode()
		} else {
			f.t.Fatal(err)
		}
	}
	if ctx.Err() != nil {
		f.t.Fatal("CLI timeout", args)
	}
	return result{code, out.String(), stderr.String()}
}

func check(t *testing.T, got result, code int, out, stderr string) {
	t.Helper()
	want := result{code, out, stderr}
	if got != want {
		t.Fatalf("got %#v; want %#v", got, want)
	}
}

const busy = "gentle-cc: shared state busy (gentle-cc.lock); see README recovery instructions\n"

func suffix(args []string) string {
	if len(args) == 0 {
		return ""
	}
	return strings.Join(args, "\n") + "\n"
}

func expected(route string, args ...string) string {
	tail := suffix(args)
	if route == "sync-all" {
		return "Official sync: pi\nsync\n--agent\npi\n" + tail +
			"Companion sync: command-code\nsync\n--agent\ncommand-code\n" + tail
	}
	return route + "\n--agent\ncommand-code\n" + tail
}

func TestSelectorsBeforeSideEffects(t *testing.T) {
	for _, route := range []string{"sync", "install", "sync-all"} {
		for _, key := range []string{"--agent", "-agent", "--agents", "-agents"} {
			for _, tokens := range [][]string{
				{key, "pi"}, {key + "=pi"}, {"--help", "--", key},
				{"--dry-run", "--preset", key + "="},
			} {
				t.Run(route+strings.Join(tokens, "_"), func(t *testing.T) {
					f := setup(t)
					f.write("{broken")
					before, _ := os.Stat(f.state)
					f.env = append(f.env, "GENTLE_AI_HOME=unsupported")
					check(t, f.run(append([]string{route}, tokens...)...), 1, "",
						"gentle-cc: agent selection is managed by the wrapper; not allowed for sync, install, or sync-all\n")
					after, _ := os.Stat(f.state)
					if f.read() != "{broken" || !before.ModTime().Equal(after.ModTime()) {
						t.Fatal("changed state")
					}
					entries, _ := os.ReadDir(filepath.Dir(f.state))
					if len(entries) != 1 {
						t.Fatal("side effect", entries)
					}
					if _, err := os.Stat(filepath.Join(f.home, "called")); !os.IsNotExist(err) {
						t.Fatal("child ran")
					}
				})
			}
		}
	}
}

func TestCustomHome(t *testing.T) {
	for _, route := range []string{"sync", "install", "sync-all"} {
		t.Run(route, func(t *testing.T) {
			f := setup(t)
			before := f.read()
			f.env = append(f.env, "GENTLE_AI_HOME= ")
			check(t, f.run(route), 1, "", "gentle-cc: GENTLE_AI_HOME is unsupported for mutating wrapper commands; unset it\n")
			if before != f.read() {
				t.Fatal("state changed")
			}
			if _, err := os.Stat(filepath.Join(filepath.Dir(f.state), "gentle-cc.lock")); !os.IsNotExist(err) {
				t.Fatal("lock side effect")
			}
			check(t, f.run(route, "--help"), 0, expected(route, "--help"), "")
		})
	}
}

func TestRoutingCleanupAndExit(t *testing.T) {
	for _, route := range []string{"sync", "install", "sync-all"} {
		for _, code := range []int{0, 7} {
			t.Run(fmt.Sprint(route, code), func(t *testing.T) {
				f := setup(t)
				f.env = append(f.env, fmt.Sprint("FIXTURE_EXIT=", code))
				r := f.run(route, "--preset=--agent=pi")
				if route == "sync-all" && code != 0 {
					check(t, r, 1, "Official sync: pi\nsync\n--agent\npi\n--preset=--agent=pi\n",
						"gentle-cc: official sync failed\n")
					return
				}
				check(t, r, code, expected(route, "--preset=--agent=pi"), "")
				if f.read() != `{"installed_agents":["pi","pi"], "other":9007199254740993123456789}` {
					t.Fatal("raw state not preserved", f.read())
				}
			})
		}
	}
}

func TestInformationalClassification(t *testing.T) {
	for _, route := range []string{"sync", "install", "sync-all"} {
		cases := [][]string{
			{"--help"}, {"-h"}, {"-dry-run"},
			{"--dry-run=false", "-dry-run=True"}, {"--dry-run=0", "--dry-run=1"},
		}
		if route != "sync-all" {
			cases = append(cases, []string{"--", "--help"}, []string{"--preset", "-help"}, []string{"positional", "--h"})
		}
		for _, flags := range cases {
			t.Run(route+strings.Join(flags, "_"), func(t *testing.T) {
				f := setup(t)
				before := f.read()
				st, _ := os.Stat(f.state)
				if err := os.Mkdir(filepath.Join(filepath.Dir(f.state), "gentle-cc.lock"), 0700); err != nil {
					t.Fatal(err)
				}
				check(t, f.run(append([]string{route}, flags...)...), 0, expected(route, flags...), "")
				after, _ := os.Stat(f.state)
				if before != f.read() || !st.ModTime().Equal(after.ModTime()) {
					t.Fatal("informational write")
				}
			})
		}
	}
}

func TestConservativeOptions(t *testing.T) {
	for _, route := range []string{"sync", "install", "sync-all"} {
		cases := [][]string{
			{"--dry-run", "-dry-run=false"}, {"--", "--dry-run"}, {"positional", "--dry-run"},
			{"--preset", "--dry-run"}, {"--unknown", "--dry-run"},
			{"--dry-run=invalid", "--dry-run"}, {"---dry-run", "--dry-run"}, {"--dry-run", "false"},
		}
		if route == "sync-all" {
			cases = append(cases, []string{"-help"}, []string{"--h"}, []string{"--", "--help"})
		}
		for _, flags := range cases {
			t.Run(route+strings.Join(flags, "_"), func(t *testing.T) {
				f := setup(t)
				before := f.read()
				if err := os.Mkdir(filepath.Join(filepath.Dir(f.state), "gentle-cc.lock"), 0700); err != nil {
					t.Fatal(err)
				}
				check(t, f.run(append([]string{route}, flags...)...), 1, "", busy)
				if before != f.read() {
					t.Fatal("busy state modified")
				}
			})
		}
	}
}

func TestSchema(t *testing.T) {
	for _, content := range []string{
		"[]", "null", `{"installed_agents":null}`, `{"installed_agents":[42]}`,
		`{"installed_agents":[null]}`, "{broken",
	} {
		t.Run(content, func(t *testing.T) {
			f := setup(t)
			f.write(content)
			r := f.run("sync-all")
			if r.code != 1 || r.out != "" || !strings.HasPrefix(r.err, "gentle-cc: cannot clean shared state: ") {
				t.Fatal(r)
			}
			if content != f.read() {
				t.Fatal("modified invalid state")
			}
			if _, err := os.Stat(filepath.Join(f.home, "called")); !os.IsNotExist(err) {
				t.Fatal("child ran")
			}
		})
	}
}

func TestNoopAndDoctor(t *testing.T) {
	f := setup(t)
	f.write("{\n \"other\": 123456789012345678901234567890, \"installed_agents\": [\"pi\"]\n}\n")
	before := f.read()
	st, _ := os.Stat(f.state)
	check(t, f.run("sync"), 0, expected("sync"), "")
	after, _ := os.Stat(f.state)
	if before != f.read() || !st.ModTime().Equal(after.ModTime()) {
		t.Fatal("no-op rewrote state")
	}
	check(t, f.run("doctor", "--agent=pi"), 0, "doctor\n--agent=pi\n", "")
}

func TestHelpUnknownAndBuildFailure(t *testing.T) {
	f := setup(t)
	for _, route := range []string{"help", "--help", "-h", "unknown"} {
		r := f.run(route, "--agent=pi")
		if r.code != 0 || r.err != "" || !strings.Contains(r.out, "standalone") || !strings.Contains(r.out, "gentle-cc sync") {
			t.Fatal(r)
		}
	}
	check(t, f.run("build"), 1, "", "gentle-cc: repo not found: "+filepath.Join(f.home, "absent")+" (set GENTLE_CC_REPO)\n")
}

func TestCleanupFailureOverridesChildExit(t *testing.T) {
	f := setup(t)
	f.env = append(f.env, "FIXTURE_EXIT=7", "FIXTURE_STATE=[]")
	check(t, f.run("sync"), 1, expected("sync"), "gentle-cc: cannot clean shared state: state must be a JSON object\n")
	if f.read() != "[]" {
		t.Fatal("changed rejected state")
	}
}

func TestNativeAtomicReplacement(t *testing.T) {
	f := setup(t)
	old, err := openOldState(f.state)
	if err != nil {
		t.Fatal(err)
	}
	defer old.Close()
	check(t, f.run("sync"), 0, expected("sync"), "")
	var value map[string]json.RawMessage
	if err := json.NewDecoder(old).Decode(&value); err != nil {
		t.Fatal(err)
	}
	if !bytes.Contains(value["installed_agents"], []byte("command-code")) {
		t.Fatal("old reader changed")
	}
	if runtime.GOOS != "windows" {
		st, _ := os.Stat(f.state)
		if st.Mode().Perm() != 0600 {
			t.Fatal(st.Mode())
		}
	}
}

func TestHardlinkLockRejected(t *testing.T) {
	f := setup(t)
	target := filepath.Join(f.home, "target")
	if err := os.WriteFile(target, []byte("unchanged"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Link(target, filepath.Join(filepath.Dir(f.state), "gentle-cc.lock")); err != nil {
		t.Skip(err)
	}
	before := f.read()
	r := f.run("sync")
	if r.code != 1 || r.out != "" || !strings.Contains(r.err, "lock") {
		t.Fatal(r)
	}
	if before != f.read() {
		t.Fatal("modified state")
	}
}

func TestSymlinkLockRejected(t *testing.T) {
	f := setup(t)
	target := filepath.Join(f.home, "target")
	if err := os.WriteFile(target, []byte("unchanged"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(target, filepath.Join(filepath.Dir(f.state), "gentle-cc.lock")); err != nil {
		t.Skip(err)
	}
	r := f.run("sync")
	if r.code != 1 || r.out != "" || !strings.Contains(r.err, "lock") {
		t.Fatal(r)
	}
}

func waitFor(t *testing.T, path string) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if _, err := os.Stat(path); err == nil {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("barrier timeout", path)
}

func TestGuardianSurvivesInvokingProcessDeath(t *testing.T) {
	f := setup(t)
	f.env = append(f.env, "FIXTURE_BARRIER=1")
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	cmd := f.command(ctx, "sync-all")
	var out, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, &stderr
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() {
		_ = os.WriteFile(filepath.Join(f.home, "release"), nil, 0600)
		if cmd.ProcessState == nil {
			_ = cmd.Process.Kill()
			_ = cmd.Wait()
		}
	}()
	waitFor(t, filepath.Join(f.home, "started"))
	before := f.read()
	check(t, f.run("install"), 1, "", busy)
	if err := cmd.Process.Kill(); err != nil {
		t.Fatal(err)
	}
	check(t, f.run("install"), 1, "", busy)
	if before != f.read() {
		t.Fatal("writer changed blocked state")
	}
	if err := os.WriteFile(filepath.Join(f.home, "release"), nil, 0600); err != nil {
		t.Fatal(err)
	}
	_ = cmd.Wait()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if !strings.Contains(f.read(), "command-code") {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	check(t, f.run("sync"), 0, expected("sync"), "")
}

func TestInternalInvocationCannotBypassGuards(t *testing.T) {
	f := setup(t)
	before := f.read()
	r := f.run("--gentle-cc-guardian", "0")
	if r.code != 1 || r.out != "" {
		t.Fatal(r)
	}
	if before != f.read() {
		t.Fatal("internal bypass changed state")
	}
}
