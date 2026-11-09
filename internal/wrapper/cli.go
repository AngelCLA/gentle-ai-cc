// Package wrapper implements the public CLI and the locked operation guardian.
// It does not contain or embed the separately distributed companion.
package wrapper

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

const selectorError = "agent selection is managed by the wrapper; not allowed for sync, install, or sync-all"
const busyError = "shared state busy (gentle-cc.lock); see README recovery instructions"

const help = `gentle-cc — Command Code companion for gentle-ai

  gentle-cc build            Build the companion binary from your branch
  gentle-cc sync    [args]   Sync only Command Code (companion)
  gentle-cc install [args]   Install only Command Code (companion)
  gentle-cc doctor  [args]   Run doctor with the companion binary
  gentle-cc sync-all [args]  Official sync for other agents + Command Code

This standalone executable needs neither Python nor Bash at runtime.
The companion remains a separate executable. Go is needed only for build.
Unknown top-level commands display this help and exit successfully.
sync/install/sync-all reject --agent, -agent, --agents, -agents, bare or =value
(also with help/dry-run or after --), before preflight, builds, binaries or writes:
gentle-cc: agent selection is managed by the wrapper; not allowed for sync, install, or sync-all
Exit status 1; stdout is empty. Embedded selector text in values is forwarded.
Mutating install/sync/sync-all reject nonempty GENTLE_AI_HOME; unset it.
Custom state homes are unsupported; help/read-only classification is unchanged.
Mutations require native OS locking (Windows, Linux, macOS), failing closed elsewhere.
The persistent OS lock file must never be removed, even when idle.
Lock directories, symlinks/reparse points and hardlinks are rejected.
A guardian holds the lock through child completion and shared-state cleanup,
including when the invoking process is terminated. Do not run direct binaries concurrently.
Failed companion null installed_agents is recovered from validated pre-child agents,
with a warning; other post-child state and the child failure status are preserved.
Pre-existing null, successful-child null and other invalid state remain errors.
Companion help (--help/-help/-h/--h) anywhere skips cleanup and locking.
sync-all only skips for unambiguous --help/-h; its official parser is unverified.
Pure -dry-run/--dry-run sequences: last value wins (Go booleans; bare = true).
False, boundaries, unknown options or possible values use preflight/lock/cleanup.
Successful mutating install adds a static Gentle AI rose mod above the editor.
The original Command Code banner stays. Existing mods are never overwritten.
Help or any potential dry-run token skips branding; sync/sync-all never add it.
Remove ~/.commandcode/mods/gentle-ai-branding.ts to opt out until next install.
See README for experimental mod API, shared-state limitations and recovery.

Env:
  GENTLE_CC_REPO   branch checkout        (default ~/dev/gentle-ai)
  GENTLE_CC_BIN    companion binary path  (Unix: ~/.local/bin/gentle-ai-cc;
                                         Windows: sibling gentle-ai-cc.exe)
  GENTLE_AI_BIN    official binary        (default gentle-ai)
`

type config struct {
	home, repo, bin, official string
}

func errorExit(message string) int {
	fmt.Fprintln(os.Stderr, "gentle-cc: "+message)
	return 1
}

func envDefault(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func configuration() (config, error) {
	// Preserve the legacy HOME contract, while supporting native Windows installs.
	home := os.Getenv("HOME")
	if home == "" {
		var err error
		home, err = os.UserHomeDir()
		if err != nil {
			return config{}, err
		}
	}
	bin := filepath.Join(home, ".local", "bin", "gentle-ai-cc")
	if runtime.GOOS == "windows" {
		executable, err := os.Executable()
		if err != nil {
			return config{}, err
		}
		bin = filepath.Join(filepath.Dir(executable), "gentle-ai-cc.exe")
	}
	return config{
		home:     home,
		repo:     envDefault("GENTLE_CC_REPO", filepath.Join(home, "dev", "gentle-ai")),
		bin:      envDefault("GENTLE_CC_BIN", bin),
		official: envDefault("GENTLE_AI_BIN", "gentle-ai"),
	}, nil
}

func protected(route string) bool {
	return route == "sync" || route == "install" || route == "sync-all"
}

func guard(args []string) error {
	if len(args) == 0 || !protected(args[0]) {
		return nil
	}
	for _, arg := range args[1:] {
		key, _, _ := strings.Cut(arg, "=")
		switch key {
		case "--agent", "-agent", "--agents", "-agents":
			return fmt.Errorf("%s", selectorError)
		}
	}
	if !informational(args[0], args[1:]) && os.Getenv("GENTLE_AI_HOME") != "" {
		return fmt.Errorf("GENTLE_AI_HOME is unsupported for mutating wrapper commands; unset it")
	}
	return nil
}

func informational(route string, args []string) bool {
	if route != "sync-all" {
		for _, arg := range args {
			switch arg {
			case "--help", "-help", "-h", "--h":
				return true
			}
		}
	}
	dryRun, isHelp := false, false
	for _, arg := range args {
		var option string
		if strings.HasPrefix(arg, "--") {
			option = arg[2:]
		} else if strings.HasPrefix(arg, "-") {
			option = arg[1:]
		} else {
			return false
		}
		switch option {
		case "help", "h":
			if arg != "--help" && arg != "-h" {
				return false
			}
			isHelp = true
		case "dry-run", "dry-run=1", "dry-run=t", "dry-run=T", "dry-run=true", "dry-run=TRUE", "dry-run=True":
			dryRun = true
		case "dry-run=0", "dry-run=f", "dry-run=F", "dry-run=false", "dry-run=FALSE", "dry-run=False":
			dryRun = false
		default:
			return false
		}
	}
	return isHelp || dryRun
}

// Main handles only public routing in the invoking process. The private pipe
// entry point never bypasses guard, schema validation, or lock acquisition.
func Main(args []string) int {
	if len(args) > 0 && args[0] == "--gentle-cc-guardian" {
		return guardianMain(args[1:])
	}
	if err := guard(args); err != nil {
		return errorExit(err.Error())
	}
	route := "help"
	if len(args) > 0 {
		route = args[0]
	}
	if route != "build" && route != "doctor" && !protected(route) {
		fmt.Print(help)
		return 0
	}
	if protected(route) && !informational(route, args[1:]) {
		return supervise(args)
	}
	cfg, err := configuration()
	if err != nil {
		return errorExit(err.Error())
	}
	switch route {
	case "build":
		return cfg.build(nil)
	case "doctor":
		if rc := cfg.ensure(nil); rc != 0 {
			return rc
		}
		return run(exec.Command(cfg.bin, append([]string{"doctor"}, args[1:]...)...), nil)
	default:
		return cfg.operation(args, nil, false)
	}
}

func (c config) build(signals *operationSignals) int {
	info, err := os.Stat(c.repo)
	if err != nil || !info.IsDir() {
		return errorExit("repo not found: " + c.repo + " (set GENTLE_CC_REPO)")
	}
	goPath, err := exec.LookPath("go")
	if err != nil {
		return errorExit("go not on PATH; required to build the companion")
	}
	fmt.Printf("Building companion from %s ...\n", c.repo)
	cmd := exec.Command(goPath, "build", "-o", c.bin, "./cmd/gentle-ai")
	cmd.Dir = c.repo
	if run(cmd, signals) != 0 {
		return errorExit("build failed")
	}
	fmt.Printf("Built %s\n", c.bin)
	return 0
}

func (c config) ensure(signals *operationSignals) int {
	info, err := os.Stat(c.bin)
	if err == nil && !info.IsDir() && (runtime.GOOS == "windows" || info.Mode()&0111 != 0) {
		return 0
	}
	return c.build(signals)
}

func (c config) operation(args []string, signals *operationSignals, mutation bool) int {
	route, flags := args[0], args[1:]
	command := route
	if route == "sync-all" {
		state, err := readState(c.home)
		if err != nil {
			return stateError(err)
		}
		if rc := c.ensure(signals); rc != 0 {
			return rc
		}
		agents := state.officialAgents()
		if agents != "" {
			fmt.Printf("Official sync: %s\n", agents)
			argv := append([]string{"sync", "--agent", agents}, flags...)
			if run(exec.Command(c.official, argv...), signals) != 0 {
				return errorExit("official sync failed")
			}
		} else {
			fmt.Println("No other agents recorded; skipping official sync.")
		}
		if signals != nil && signals.stopped() != 0 {
			return signals.stopped()
		}
		fmt.Println("Companion sync: command-code")
		command = "sync"
	}
	if rc := c.ensure(signals); rc != 0 {
		return rc
	}
	var before sharedState
	if mutation {
		var err error
		// In sync-all this is after official sync: do not roll its agent list back.
		before, err = readState(c.home)
		if err != nil {
			return stateError(err)
		}
	}
	argv := append([]string{command, "--agent", "command-code"}, flags...)
	rc := run(exec.Command(c.bin, argv...), signals)
	if mutation {
		recovered := false
		if rc != 0 {
			var err error
			recovered, err = recoverFailedState(c.home, before)
			if err != nil {
				return stateError(err)
			}
			if recovered {
				fmt.Fprintln(os.Stderr, "gentle-cc: warning: recovered installed_agents from pre-companion state after companion failure; other state preserved")
			}
		}
		if !recovered {
			if err := cleanState(c.home); err != nil {
				return stateError(err)
			}
		}
	}
	if mutation && rc == 0 && brandingRequested(args) {
		c.brand(signals)
	}
	return rc
}
