package wrapper

import (
	"bytes"
	_ "embed"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

//go:embed gentle-ai-branding.ts
var brandingMod []byte

const brandingName = "gentle-ai-branding.ts"
const brandingWarning = "gentle-cc: warning: Gentle AI branding not installed; existing or unsafe path preserved (see README)"

// This is deliberately independent of informational: ambiguous dry-runs still
// retain their existing lock/cleanup semantics, but never opt into branding.
func brandingRequested(args []string) bool {
	if args[0] != "install" {
		return false
	}
	for _, arg := range args[1:] {
		if strings.Contains(arg, "dry-run") {
			return false
		}
		switch arg {
		case "--help", "-help", "-h", "--h":
			return false
		}
	}
	return true
}

func (c config) brand(signals *operationSignals) {
	// Serialize cancellation with this short, local-only publication. An already
	// cancelled install cannot create directories or publish a mod.
	if signals != nil {
		signals.mu.Lock()
		defer signals.mu.Unlock()
		if signals.code != 0 {
			return
		}
	}
	if err := installBranding(c.home); err != nil {
		fmt.Fprintln(os.Stderr, brandingWarning)
	}
}

// Open each component relative to a pinned directory handle. Root confines path
// resolution even during swaps; the identity check also rejects links to other
// directories inside that root. Never use MkdirAll or reopen an absolute path.
func brandingDirectory(parent *os.Root, name string, create bool) (*os.Root, error) {
	info, err := parent.Lstat(name)
	if os.IsNotExist(err) && create {
		if err = parent.Mkdir(name, 0700); err != nil && !os.IsExist(err) {
			return nil, err
		}
		info, err = parent.Lstat(name)
	}
	if err != nil {
		return nil, err
	}
	if !info.IsDir() || info.Mode()&(os.ModeSymlink|os.ModeIrregular) != 0 {
		return nil, fmt.Errorf("unsafe branding directory")
	}
	dir, err := parent.OpenRoot(name)
	if err != nil {
		return nil, err
	}
	opened, err := dir.Stat(".")
	if err != nil || !os.SameFile(info, opened) {
		dir.Close()
		return nil, fmt.Errorf("branding directory changed")
	}
	return dir, nil
}

func installBranding(home string) error {
	absolute, err := filepath.Abs(home)
	if err != nil {
		return err
	}
	volume := filepath.VolumeName(absolute)
	dir, err := os.OpenRoot(volume + string(filepath.Separator))
	if err != nil {
		return err
	}
	// Reject linked ancestors too, including a linked HOME. Only the two owned
	// configuration directories may be created; HOME must already exist.
	parts := strings.Split(strings.TrimPrefix(absolute, volume), string(filepath.Separator))
	for i, part := range append(parts, ".commandcode", "mods") {
		if part == "" {
			continue
		}
		next, openErr := brandingDirectory(dir, part, i >= len(parts))
		if openErr != nil {
			dir.Close()
			return openErr
		}
		dir.Close()
		dir = next
	}
	defer dir.Close()
	return publishBranding(dir)
}

func publishBranding(dir *os.Root) error {
	file, err := dir.OpenFile(brandingName, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if os.IsExist(err) {
		info, statErr := dir.Lstat(brandingName)
		if statErr != nil || !info.Mode().IsRegular() {
			return fmt.Errorf("branding conflict")
		}
		// Read only a bounded regular file and verify the opened identity. Root
		// prevents escape if a link is substituted between Lstat and Open.
		file, err = dir.Open(brandingName)
		if err != nil {
			return err
		}
		defer file.Close()
		opened, statErr := file.Stat()
		if statErr != nil || !os.SameFile(info, opened) {
			return fmt.Errorf("branding file changed")
		}
		data, readErr := io.ReadAll(io.LimitReader(file, int64(len(brandingMod)+1)))
		if readErr != nil || !bytes.Equal(data, brandingMod) {
			return fmt.Errorf("branding conflict")
		}
		return nil
	}
	if err != nil {
		return err
	}
	// O_EXCL never follows an existing symlink or replaces existing content.
	// On write/close failure leave the owned partial file and warn, never retry
	// by truncating or deleting a path that another process could have changed.
	_, writeErr := file.Write(brandingMod)
	if writeErr == nil {
		writeErr = file.Sync()
	}
	closeErr := file.Close()
	if writeErr != nil {
		return writeErr
	}
	return closeErr
}
