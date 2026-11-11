package dataroot

import (
	"os"
	"path/filepath"
	"testing"
)

func TestPointerRoundTrip(t *testing.T) {
	file := filepath.Join(t.TempDir(), "data_root.txt")
	t.Setenv("JM_DATA_POINTER", file)
	target := filepath.Join(t.TempDir(), "library")
	if err := Write(target); err != nil {
		t.Fatal(err)
	}
	got, ok := Read()
	if !ok || got != filepath.Clean(target) {
		t.Fatalf("read %q %v", got, ok)
	}
}

func TestReadIgnoresRelativePointer(t *testing.T) {
	file := filepath.Join(t.TempDir(), "data_root.txt")
	t.Setenv("JM_DATA_POINTER", file)
	if err := os.WriteFile(file, []byte("comics\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, ok := Read(); ok {
		t.Fatal("relative pointer should be ignored")
	}
}

func TestMoveRenamesDirectory(t *testing.T) {
	root := t.TempDir()
	src := filepath.Join(root, "old")
	dst := filepath.Join(root, "new")
	if err := os.MkdirAll(filepath.Join(src, "comics"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(src, "comics", "note.txt"), []byte("page"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := Move(src, dst); err != nil {
		t.Fatal(err)
	}
	body, err := os.ReadFile(filepath.Join(dst, "comics", "note.txt"))
	if err != nil || string(body) != "page" {
		t.Fatalf("moved file %q %v", body, err)
	}
	if _, err := os.Stat(src); !os.IsNotExist(err) {
		t.Fatalf("source still exists: %v", err)
	}
}

func TestMoveRejectsNonEmptyDestination(t *testing.T) {
	root := t.TempDir()
	src := filepath.Join(root, "old")
	dst := filepath.Join(root, "new")
	if err := os.MkdirAll(src, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(dst, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dst, "keep.txt"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := Move(src, dst); err == nil {
		t.Fatal("expected rejection")
	}
	if _, err := os.Stat(filepath.Join(dst, "keep.txt")); err != nil {
		t.Fatal(err)
	}
}

func TestInside(t *testing.T) {
	if !Inside("/data/library", "/data/library/comics") {
		t.Fatal("child")
	}
	if Inside("/data/library", "/data/library") {
		t.Fatal("same path is not inside")
	}
	if Inside("/data/library", "/data/other") {
		t.Fatal("sibling")
	}
}
