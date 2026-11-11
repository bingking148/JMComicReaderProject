package app

import (
	"archive/zip"
	"os"
	"path/filepath"
	"testing"

	"github.com/bingking148/JMComicReaderProject/engine/internal/library"
)

func TestImportLegacyFolderZipAndSkipComplete(t *testing.T) {
	dir := t.TempDir()
	application, err := OpenWith(dir, &fakeCatalog{})
	if err != nil {
		t.Fatal(err)
	}
	legacy := filepath.Join(t.TempDir(), "9_旧书架")
	if err := os.MkdirAll(legacy, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(legacy, "00001.jpg"), []byte("page-a"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(legacy, "00002.jpg"), []byte("page-b"), 0o644); err != nil {
		t.Fatal(err)
	}

	report, err := application.ImportPath(legacy)
	if err != nil {
		t.Fatal(err)
	}
	if report.Imported != 1 || report.Skipped != 0 {
		t.Fatalf("first import %+v", report)
	}
	lib, err := application.ListLibrary()
	if err != nil || len(lib) != 1 || lib[0].ID != 9 || lib[0].Pages != 2 {
		t.Fatalf("library %+v %v", lib, err)
	}

	again, err := application.ImportPath(legacy)
	if err != nil {
		t.Fatal(err)
	}
	if again.Skipped != 1 || again.Imported != 0 {
		t.Fatalf("second import %+v", again)
	}
	kept, err := os.ReadFile(filepath.Join(lib[0].Dir, "00001.jpg"))
	if err != nil {
		t.Fatal(err)
	}
	if string(kept) != "page-a" {
		t.Fatalf("complete page changed to %q", kept)
	}

	partialDir := filepath.Join(dir, "comics", "10_半本")
	if err := os.MkdirAll(partialDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(partialDir, "00001.jpg"), []byte("keep"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := application.Library.Upsert(library.Comic{
		ID: 10, Title: "半本", Dir: partialDir, Status: "partial", Page: 1,
	}); err != nil {
		t.Fatal(err)
	}
	extra := filepath.Join(t.TempDir(), "10_半本")
	if err := os.MkdirAll(extra, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(extra, "00001.jpg"), []byte("replace"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(extra, "00002.jpg"), []byte("new"), 0o644); err != nil {
		t.Fatal(err)
	}
	merged, err := application.ImportPath(extra)
	if err != nil {
		t.Fatal(err)
	}
	if merged.Merged != 1 {
		t.Fatalf("merge %+v", merged)
	}
	first, _ := os.ReadFile(filepath.Join(partialDir, "00001.jpg"))
	second, err := os.ReadFile(filepath.Join(partialDir, "00002.jpg"))
	if err != nil || string(first) != "keep" || string(second) != "new" {
		t.Fatalf("merged files %q %q %v", first, second, err)
	}

	zipPath := filepath.Join(t.TempDir(), "11_压缩.cbz")
	if err := writeZip(zipPath, map[string]string{"00001.jpg": "z"}); err != nil {
		t.Fatal(err)
	}
	fromZip, err := application.ImportPath(zipPath)
	if err != nil {
		t.Fatal(err)
	}
	if fromZip.Imported != 1 {
		t.Fatalf("zip %+v", fromZip)
	}
	if _, err := application.Reader(11); err != nil {
		t.Fatal(err)
	}

	evil := filepath.Join(t.TempDir(), "12_evil.zip")
	if err := writeZip(evil, map[string]string{"../escape.txt": "no"}); err != nil {
		t.Fatal(err)
	}
	if _, err := application.ImportPath(evil); err == nil {
		t.Fatal("zip slip was accepted")
	}
	if _, err := os.Stat(filepath.Join(dir, "escape.txt")); !os.IsNotExist(err) {
		t.Fatal("zip slip wrote outside the temp dir")
	}

	parent := t.TempDir()
	one := filepath.Join(parent, "13_甲")
	two := filepath.Join(parent, "comics", "14_乙")
	if err := os.MkdirAll(one, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(two, 0o755); err != nil {
		t.Fatal(err)
	}
	_ = os.WriteFile(filepath.Join(one, "00003.png"), []byte("a"), 0o644)
	_ = os.WriteFile(filepath.Join(two, "00004.png"), []byte("b"), 0o644)
	batch, err := application.ImportPath(parent)
	if err != nil {
		t.Fatal(err)
	}
	if batch.Imported != 2 {
		t.Fatalf("batch %+v", batch)
	}
}

func writeZip(path string, files map[string]string) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()
	zw := zip.NewWriter(f)
	for name, body := range files {
		w, err := zw.Create(name)
		if err != nil {
			return err
		}
		if _, err := w.Write([]byte(body)); err != nil {
			return err
		}
	}
	return zw.Close()
}
