package wrapper_test

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

func brandingPath(f *fixture) string {
	return filepath.Join(f.home, ".commandcode", "mods", "gentle-ai-branding.ts")
}

func assertNoBranding(t *testing.T, f *fixture) {
	t.Helper()
	if _, err := os.Lstat(brandingPath(f)); !os.IsNotExist(err) {
		t.Fatalf("unexpected branding file: %v", err)
	}
}

func TestBrandingInstallAndSync(t *testing.T) {
	f := setup(t)
	check(t, f.run("install", "--preset", "full-gentleman"), 0, expected("install", "--preset", "full-gentleman"), "")
	data, err := os.ReadFile(brandingPath(f))
	if err != nil {
		t.Fatal(err)
	}
	for _, marker := range []string{"cmd.ui.widget", "above-editor", "render: () => [", "Gentle AI", "export default function (cmd)"} {
		if !strings.Contains(string(data), marker) {
			t.Fatalf("missing mod marker %q", marker)
		}
	}
	if strings.Contains(f.read(), "command-code") {
		t.Fatal("install did not clean state")
	}
	before, _ := os.Stat(brandingPath(f))
	check(t, f.run("install"), 0, expected("install"), "")
	after, _ := os.Stat(brandingPath(f))
	if !os.SameFile(before, after) || !before.ModTime().Equal(after.ModTime()) {
		t.Fatal("identical mod rewritten")
	}
	// Simulate the user's removal in the isolated home.
	if err := os.Remove(brandingPath(f)); err != nil {
		t.Fatal(err)
	}
	for _, route := range []string{"sync", "sync-all", "doctor"} {
		out := expected(route)
		if route == "doctor" {
			out = "doctor\n"
		}
		check(t, f.run(route), 0, out, "")
		assertNoBranding(t, f)
	}
}

func TestBrandingFactory(t *testing.T) {
	f := setup(t)
	check(t, f.run("install"), 0, expected("install"), "")
	data, err := os.ReadFile(brandingPath(f))
	if err != nil {
		t.Fatal(err)
	}
	node, err := exec.LookPath("node")
	if err != nil {
		if !strings.Contains(string(data), "export default function (cmd)") || strings.Contains(string(data), "import ") || strings.Contains(string(data), "defineMod") {
			t.Fatal("expected dependency-free default factory")
		}
		t.Log("Node unavailable: structural factory check only; loader unverified")
		return
	}
	// Execute the exact installed asset as an ES module, without dependencies,
	// package discovery or a TypeScript loader. Only the documented API is mocked.
	const script = `
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const source = readFileSync(0, 'utf8');
const mod = await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'));
assert.equal(typeof mod.default, 'function');
assert.deepEqual(Object.keys(mod), ['default']);
const widgets = [];
const rejectUnknown = { get(target, key) {
  assert.ok(Object.hasOwn(target, key), 'unexpected API access: ' + String(key));
  return target[key];
} };
const ui = new Proxy({ widget: options => widgets.push(options) }, rejectUnknown);
const cmd = new Proxy({ ui }, rejectUnknown);
assert.equal(mod.default(cmd), undefined);
assert.equal(widgets.length, 1);
assert.deepEqual(Object.keys(widgets[0]).sort(), ['placement', 'render']);
assert.equal(widgets[0].placement, 'above-editor');
assert.equal(typeof widgets[0].render, 'function');
assert.deepEqual(widgets[0].render(), ["\u001b[38;2;255;121;198mPowered by Gentle AI\u001b[0m"]);
assert.deepEqual(widgets[0].render(), ["\u001b[38;2;255;121;198mPowered by Gentle AI\u001b[0m"]);
`
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, node, "--input-type=module", "-e", script)
	cmd.Env = f.env
	cmd.Dir = f.home
	cmd.Stdin = strings.NewReader(string(data))
	output, err := cmd.CombinedOutput()
	if err != nil || len(output) != 0 {
		t.Fatalf("factory mock: %v\n%s", err, output)
	}
}

func TestBrandingFreshSync(t *testing.T) {
	for _, route := range []string{"sync", "sync-all"} {
		f := setup(t)
		check(t, f.run(route), 0, expected(route), "")
		if _, err := os.Stat(filepath.Join(f.home, ".commandcode")); !os.IsNotExist(err) {
			t.Fatal("sync created branding directories", err)
		}
	}
}

func TestBrandingCancelledInstall(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("requires native console Control-Break; Unix interrupt only here")
	}
	f := setup(t)
	f.env = append(f.env, "FIXTURE_BARRIER=1", "FIXTURE_IGNORE_SIGNALS=1")
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	cmd := f.command(ctx, "install")
	// No inherited output pipes: the guardian intentionally outlives its parent.
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
	if err := cmd.Process.Signal(os.Interrupt); err != nil {
		t.Fatal(err)
	}
	err := cmd.Wait()
	if exit, ok := err.(*exec.ExitError); !ok || exit.ExitCode() != 130 {
		t.Fatalf("cancelled install: %v", err)
	}
	check(t, f.run("install"), 1, "", busy)
	if err := os.WriteFile(filepath.Join(f.home, "release"), nil, 0600); err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(5 * time.Second)
	for strings.Contains(f.read(), "command-code") && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	// A subsequent sync proves the guardian finished and released the lock.
	check(t, f.run("sync"), 0, expected("sync"), "")
	assertNoBranding(t, f)
}

func TestBrandingSkippedInvocations(t *testing.T) {
	for _, flags := range [][]string{
		{"--help"}, {"positional", "--h"}, {"--preset", "-help"},
		{"--dry-run"}, {"--preset", "full", "--dry-run"},
		{"--dry-run=false"}, {"--", "--dry-run"},
		{"--dry-run=invalid"}, {"---dry-run"}, {"--dry-run", "false"},
		{"--dry-run", "-dry-run=false"}, {"--preset=--dry-run"},
	} {
		t.Run(strings.Join(flags, "_"), func(t *testing.T) {
			f := setup(t)
			before := f.read()
			check(t, f.run(append([]string{"install"}, flags...)...), 0, expected("install", flags...), "")
			assertNoBranding(t, f)
			// Existing routing, including conservative cleanup, is unchanged.
			informational := strings.Contains(strings.Join(flags, " "), "help") || strings.Contains(strings.Join(flags, " "), "--h") || len(flags) == 1 && flags[0] == "--dry-run"
			if informational && f.read() != before {
				t.Fatal("help/pure dry-run changed state")
			}
		})
	}
}

func TestBrandingFailures(t *testing.T) {
	for _, cleanupFailure := range []bool{false, true} {
		f := setup(t)
		f.env = append(f.env, "FIXTURE_EXIT=7")
		code, stderr := 7, ""
		if cleanupFailure {
			f.env = append(f.env, "FIXTURE_STATE=[]")
			code, stderr = 1, "gentle-cc: cannot clean shared state: state must be a JSON object\n"
		}
		check(t, f.run("install"), code, expected("install"), stderr)
		assertNoBranding(t, f)
	}
}

const brandingWarning = "gentle-cc: warning: Gentle AI branding not installed; existing or unsafe path preserved (see README)\n"

func TestBrandingConflicts(t *testing.T) {
	for _, kind := range []string{"custom", "directory", "symlink-file", "symlink-mods", "symlink-commandcode", "symlink-home", "blocked-parent"} {
		t.Run(kind, func(t *testing.T) {
			f := setup(t)
			target := filepath.Join(f.home, "untouched")
			if err := os.Mkdir(target, 0700); err != nil {
				t.Fatal(err)
			}
			path := brandingPath(f)
			switch kind {
			case "symlink-home":
				alias := filepath.Join(f.home, "home-link")
				if err := os.Symlink(f.home, alias); err != nil {
					t.Skip(err)
				}
				f.env = append(f.env, "HOME="+alias)
			case "symlink-commandcode", "blocked-parent":
				path = filepath.Join(f.home, ".commandcode")
			case "symlink-mods":
				path = filepath.Dir(path)
			}
			if kind != "symlink-home" {
				if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
					t.Fatal(err)
				}
				switch kind {
				case "custom", "blocked-parent":
					if err := os.WriteFile(path, []byte("user content"), 0600); err != nil {
						t.Fatal(err)
					}
				case "directory":
					if err := os.Mkdir(path, 0700); err != nil {
						t.Fatal(err)
					}
				default:
					if err := os.Symlink(target, path); err != nil {
						t.Skip(err)
					}
				}
			}
			before, err := os.Lstat(path)
			if err != nil && kind != "symlink-home" {
				t.Fatal(err)
			}
			check(t, f.run("install"), 0, expected("install"), brandingWarning)
			if kind != "symlink-home" {
				after, err := os.Lstat(path)
				if err != nil || !os.SameFile(before, after) || !before.ModTime().Equal(after.ModTime()) {
					t.Fatal("conflict replaced", err)
				}
			}
			if kind == "custom" || kind == "blocked-parent" {
				data, _ := os.ReadFile(path)
				if string(data) != "user content" {
					t.Fatal("custom content changed")
				}
			}
			entries, _ := os.ReadDir(target)
			if len(entries) != 0 || strings.Contains(f.read(), "command-code") {
				t.Fatal("followed link or skipped cleanup")
			}
		})
	}
}
