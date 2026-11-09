package wrapper_test

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

const recoveryWarning = "gentle-cc: warning: recovered installed_agents from pre-companion state after companion failure; other state preserved\n"

func checkCalls(t *testing.T, f *fixture, count int) {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(f.home, "called"))
	if count == 0 && os.IsNotExist(err) {
		return
	}
	if err != nil || string(data) != strings.Repeat(filepath.Base(child)+"\n", count) {
		t.Fatalf("child calls: %q, %v; want %d", data, err, count)
	}
}

func TestFailedCompanionNullRecovery(t *testing.T) {
	for _, route := range []string{"install", "sync", "sync-all"} {
		for _, initial := range []string{"missing", `{"other":1}`, `{"installed_agents":["command-code","pi","pi","commandcode","opencode"]}`} {
			t.Run(route+initial, func(t *testing.T) {
				f := setup(t)
				if initial == "missing" {
					if err := os.Remove(f.state); err != nil {
						t.Fatal(err)
					}
				} else {
					f.write(initial)
					if err := os.Chmod(f.state, 0640); err != nil {
						t.Fatal(err)
					}
				}
				// Keep all companion updates except the effective null field.
				post := "{\n \"other\":9007199254740993123456789, \"counter\":73, \"installed_agents\" : null, \"nested\":{\"installed_agents\":null}\n}\n"
				f.env = append(f.env, "FIXTURE_COMPANION_STATE="+post, "FIXTURE_COMPANION_EXIT=7")
				out, count, restored := expected(route), 1, `["pi","pi","opencode"]`
				if initial == "missing" || initial == `{"other":1}` {
					restored = `[]`
					if route == "sync-all" {
						out = "No other agents recorded; skipping official sync.\nCompanion sync: command-code\nsync\n--agent\ncommand-code\n"
					}
				} else if route == "sync-all" {
					out = "Official sync: pi,opencode\nsync\n--agent\npi,opencode\nCompanion sync: command-code\nsync\n--agent\ncommand-code\n"
					count = 2
				}
				check(t, f.run(route), 7, out, recoveryWarning)
				if got := f.read(); got != strings.Replace(post, ": null", ": "+restored, 1) {
					t.Fatalf("recovered state: %s", got)
				}
				st, err := os.Stat(f.state)
				if err != nil {
					t.Fatal(err)
				}
				mode := os.FileMode(0640)
				if initial == "missing" {
					mode = 0600
				}
				if runtime.GOOS != "windows" && st.Mode().Perm() != mode {
					t.Fatal(st.Mode())
				}
				checkCalls(t, f, count)
			})
		}
	}
}

func TestRecoveryAfterOfficialSync(t *testing.T) {
	f := setup(t)
	f.env = append(f.env,
		`FIXTURE_STATE={"installed_agents":["vscode-copilot","pi","pi","commandcode"],"official_counter":9}`,
		`FIXTURE_COMPANION_STATE={"installed_agents":null,"official_counter":10,"companion_counter":1}`,
		"FIXTURE_COMPANION_EXIT=23")
	check(t, f.run("sync-all"), 23, expected("sync-all"), recoveryWarning)
	if got := f.read(); got != `{"installed_agents":["vscode-copilot","pi","pi"],"official_counter":10,"companion_counter":1}` {
		t.Fatal(got)
	}
	checkCalls(t, f, 2)
}

func TestRecoveryRejectsInvalidState(t *testing.T) {
	for _, route := range []string{"install", "sync", "sync-all"} {
		for _, stage := range []string{"before", "failed", "successful"} {
			for _, invalid := range []struct{ content, detail string }{
				{`{"installed_agents":null,"counter":4}`, "installed_agents must be a list of strings"},
				{`{"installed_agents":["pi",null],"counter":4}`, "installed_agents must be a list of strings"},
				{`{"installed_agents":["pi",42],"counter":4}`, "installed_agents must be a list of strings"},
				{`{"installed_agents":null} trailing`, "invalid character 'a' in literal true (expecting 'u')"},
			} {
				if stage == "failed" && invalid.content == `{"installed_agents":null,"counter":4}` {
					continue // This is the authorized recovery, tested above.
				}
				t.Run(route+stage+invalid.content, func(t *testing.T) {
					f := setup(t)
					out, count := expected(route), 1
					if route == "sync-all" {
						count = 2
					}
					code := "7"
					if stage == "successful" {
						code = "0"
					}
					if stage == "before" {
						f.write(invalid.content)
						out, count = "", 0
					} else {
						f.env = append(f.env, "FIXTURE_COMPANION_STATE="+invalid.content, "FIXTURE_COMPANION_EXIT="+code)
					}
					check(t, f.run(route), 1, out, "gentle-cc: cannot clean shared state: "+invalid.detail+"\n")
					if f.read() != invalid.content {
						t.Fatal("rejected state changed", f.read())
					}
					checkCalls(t, f, count)
				})
			}
		}
	}
}

func TestRecoveryPreservesOrdinaryCleanup(t *testing.T) {
	for _, route := range []string{"install", "sync", "sync-all"} {
		f := setup(t)
		f.env = append(f.env, "FIXTURE_COMPANION_EXIT=7")
		check(t, f.run(route), 7, expected(route), "")
		if f.read() != `{"installed_agents":["pi","pi"], "other":9007199254740993123456789}` {
			t.Fatal(f.read())
		}
	}
}

func TestRecoveryUsesEffectiveDuplicateKey(t *testing.T) {
	f := setup(t)
	f.write(`{"installed_agents":null,"installed_agents":["pi","pi","commandcode"]}`)
	f.env = append(f.env, `FIXTURE_COMPANION_STATE={"installed_agents":[42],"installed_agents":null,"counter":3}`, "FIXTURE_COMPANION_EXIT=7")
	check(t, f.run("sync"), 7, expected("sync"), recoveryWarning)
	if f.read() != `{"installed_agents":[42],"installed_agents":["pi","pi"],"counter":3}` {
		t.Fatal(f.read())
	}
	checkCalls(t, f, 1)
}

func TestRecoveryDoesNotRepairOfficialNull(t *testing.T) {
	f := setup(t)
	post := `{"installed_agents":null,"counter":8}`
	f.env = append(f.env, "FIXTURE_STATE="+post, "FIXTURE_COMPANION_EXIT=7")
	check(t, f.run("sync-all"), 1, "Official sync: pi\nsync\n--agent\npi\nCompanion sync: command-code\n", "gentle-cc: cannot clean shared state: installed_agents must be a list of strings\n")
	if f.read() != post {
		t.Fatal(f.read())
	}
	checkCalls(t, f, 1)
}

func TestRecoverySkipsInformationalCalls(t *testing.T) {
	for _, route := range []string{"install", "sync", "sync-all"} {
		f := setup(t)
		post := `{"installed_agents":null,"counter":8}`
		f.env = append(f.env, "FIXTURE_COMPANION_STATE="+post, "FIXTURE_COMPANION_EXIT=7")
		check(t, f.run(route, "--help"), 7, expected(route, "--help"), "")
		if f.read() != post {
			t.Fatal(f.read())
		}
		count := 1
		if route == "sync-all" {
			count = 2
		}
		checkCalls(t, f, count)
	}
}
