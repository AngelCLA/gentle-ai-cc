//go:build windows

package wrapper_test

import (
	"io"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"unsafe"
)

// Isolated API diagnostic: no shared state or production executable is involved.
// Keep the MoveFileExW comparison as evidence, not as a required failure on every
// Windows filesystem. ReplaceFileW must preserve open readers and publish bytes.
func TestWindowsReplacementProbe(t *testing.T) {
	kernel := syscall.NewLazyDLL("kernel32.dll")
	for _, api := range []string{"MoveFileExW", "ReplaceFileW"} {
		for _, reader := range []string{"closed", "delete-sharing"} {
			t.Run(api+"/"+reader, func(t *testing.T) {
				dir := t.TempDir()
				target, source := filepath.Join(dir, "target"), filepath.Join(dir, "source")
				for _, path := range []string{target, source} {
					if err := os.WriteFile(path, []byte(path), 0600); err != nil {
						t.Fatal(err)
					}
				}
				to, _ := syscall.UTF16PtrFromString(target)
				from, _ := syscall.UTF16PtrFromString(source)
				attrs, err := syscall.GetFileAttributes(to)
				if err != nil {
					t.Fatal(err)
				}
				t.Logf("target attributes=%#x readonly=%t", attrs, attrs&syscall.FILE_ATTRIBUTE_READONLY != 0)
				var old *os.File
				if reader == "delete-sharing" {
					old, err = openOldState(target)
					if err != nil {
						t.Fatal(err)
					}
					defer old.Close()
					var flags uint32
					ok, _, err := kernel.NewProc("GetHandleInformation").Call(old.Fd(), uintptr(unsafe.Pointer(&flags)))
					if ok == 0 {
						t.Fatal(err)
					}
					t.Logf("old-reader handle flags=%#x inheritable=%t", flags, flags&syscall.HANDLE_FLAG_INHERIT != 0)
					if flags&syscall.HANDLE_FLAG_INHERIT != 0 {
						t.Fatal("old reader must not leak to child processes")
					}
				}
				var ok uintptr
				var callErr error
				if api == "MoveFileExW" {
					ok, _, callErr = kernel.NewProc(api).Call(uintptr(unsafe.Pointer(from)), uintptr(unsafe.Pointer(to)), 9)
				} else {
					ok, _, callErr = kernel.NewProc(api).Call(uintptr(unsafe.Pointer(to)), uintptr(unsafe.Pointer(from)), 0, 0, 0, 0)
				}
				t.Logf("result=%d error=%v", ok, callErr)
				if api == "ReplaceFileW" && ok == 0 {
					t.Fatal("replacement failed", callErr)
				}
				if ok != 0 {
					data, err := os.ReadFile(target)
					if err != nil || string(data) != source {
						t.Fatalf("replacement bytes: %q, %v", data, err)
					}
				}
				if old != nil {
					data, err := io.ReadAll(old)
					if err != nil || string(data) != target {
						t.Fatalf("old reader bytes: %q, %v", data, err)
					}
				}
			})
		}
	}
}

func TestWindowsReplacementFailurePreservesState(t *testing.T) {
	f := setup(t)
	before := f.read()
	info, err := os.Stat(f.state)
	if err != nil {
		t.Fatal(err)
	}
	// A normal Go reader does not grant FILE_SHARE_DELETE. It intentionally
	// prevents replacement; the wrapper must fail without altering old state.
	old, err := os.Open(f.state)
	if err != nil {
		t.Fatal(err)
	}
	defer old.Close()
	got := f.run("sync")
	if got.code != 1 || got.out != expected("sync") || !strings.HasPrefix(got.err, "gentle-cc: cannot clean shared state: ") {
		t.Fatalf("unexpected failure result: %#v", got)
	}
	after, err := os.Stat(f.state)
	if err != nil {
		t.Fatal(err)
	}
	if f.read() != before || !info.ModTime().Equal(after.ModTime()) || !os.SameFile(info, after) {
		t.Fatal("failed replacement changed original state")
	}
	data, err := io.ReadAll(old)
	if err != nil || string(data) != before {
		t.Fatalf("failed replacement changed old reader: %q, %v", data, err)
	}
	entries, err := os.ReadDir(filepath.Dir(f.state))
	if err != nil || len(entries) != 2 || entries[0].Name() != "gentle-cc.lock" || entries[1].Name() != "state.json" {
		t.Fatalf("replacement leaked scratch or removed persistent files: %v, %v", entries, err)
	}
}
