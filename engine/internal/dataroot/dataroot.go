// Package dataroot tracks where bulky library data lives.
// The pointer file is intentionally outside that directory so the app can
// still find the library after it moves.
package dataroot

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

// Result is what a library move or path switch reports to the UI.
type Result struct {
	OldPath string `json:"oldPath"`
	NewPath string `json:"newPath"`
	Moved   bool   `json:"moved"`
	Restart bool   `json:"restart"`
}

// PointerFile is the small user-writable file that records the library path.
// JM_DATA_POINTER overrides it for tests.
func PointerFile() (string, error) {
	if override := strings.TrimSpace(os.Getenv("JM_DATA_POINTER")); override != "" {
		return override, nil
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	switch runtime.GOOS {
	case "windows":
		base := os.Getenv("APPDATA")
		if base == "" {
			base = filepath.Join(home, "AppData", "Roaming")
		}
		return filepath.Join(base, "JMComicReader", "data_root.txt"), nil
	case "darwin":
		return filepath.Join(home, "Library", "Preferences", "JMComicReader", "data_root.txt"), nil
	default:
		base := os.Getenv("XDG_CONFIG_HOME")
		if base == "" {
			base = filepath.Join(home, ".config")
		}
		return filepath.Join(base, "JMComicReader", "data_root.txt"), nil
	}
}

// Read returns the saved absolute library path.
func Read() (string, bool) {
	file, err := PointerFile()
	if err != nil {
		return "", false
	}
	body, err := os.ReadFile(file)
	if err != nil {
		return "", false
	}
	line := strings.TrimSpace(strings.Split(strings.ReplaceAll(string(body), "\r\n", "\n"), "\n")[0])
	if line == "" || !filepath.IsAbs(line) {
		return "", false
	}
	return filepath.Clean(line), true
}

// Write stores the library path. It does not delete any previous library.
func Write(path string) error {
	clean, err := CleanAbs(path)
	if err != nil {
		return err
	}
	file, err := PointerFile()
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(file), 0o755); err != nil {
		return err
	}
	tmp := file + ".tmp"
	if err := os.WriteFile(tmp, []byte(clean+"\n"), 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, file)
}

// CleanAbs rejects relative paths and trims a trailing separator.
func CleanAbs(path string) (string, error) {
	path = strings.TrimSpace(path)
	if path == "" {
		return "", fmt.Errorf("请填写数据目录")
	}
	if !filepath.IsAbs(path) {
		return "", fmt.Errorf("数据目录需要是绝对路径")
	}
	return filepath.Clean(path), nil
}

// Same reports whether two directories are the same path.
func Same(a, b string) bool {
	if runtime.GOOS == "windows" {
		return strings.EqualFold(filepath.Clean(a), filepath.Clean(b))
	}
	return filepath.Clean(a) == filepath.Clean(b)
}

// Inside reports whether child is within parent, and is not parent itself.
func Inside(parent, child string) bool {
	rel, err := filepath.Rel(filepath.Clean(parent), filepath.Clean(child))
	if err != nil {
		return false
	}
	return rel != "." && rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))
}

// Move relocates a library directory.
// Choosing move removes the source after a successful transfer.
// The destination must be missing or empty.
func Move(src, dst string) error {
	src = filepath.Clean(src)
	dst = filepath.Clean(dst)
	info, err := os.Stat(src)
	if err != nil {
		return fmt.Errorf("找不到当前数据目录: %w", err)
	}
	if !info.IsDir() {
		return fmt.Errorf("当前数据目录不是文件夹")
	}
	empty, err := IsEmpty(dst)
	if err != nil {
		return err
	}
	if !empty {
		return fmt.Errorf("目标目录不是空的，请换一个新文件夹，或选择“只改路径”")
	}
	if _, err := os.Stat(dst); os.IsNotExist(err) {
		if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
			return err
		}
		if err := os.Rename(src, dst); err == nil {
			return nil
		}
	}
	if err := os.MkdirAll(dst, 0o755); err != nil {
		return err
	}
	if err := copyTree(src, dst); err != nil {
		_ = os.RemoveAll(dst)
		return err
	}
	if err := os.RemoveAll(src); err != nil {
		return fmt.Errorf("数据已复制到新目录，但旧目录还在: %w", err)
	}
	return nil
}

// IsEmpty is true when the directory does not exist or has no entries.
func IsEmpty(path string) (bool, error) {
	dir, err := os.Open(path)
	if os.IsNotExist(err) {
		return true, nil
	}
	if err != nil {
		return false, err
	}
	defer dir.Close()
	info, err := dir.Stat()
	if err != nil {
		return false, err
	}
	if !info.IsDir() {
		return false, fmt.Errorf("目标不是文件夹")
	}
	_, err = dir.Readdirnames(1)
	if err == io.EOF {
		return true, nil
	}
	if err != nil {
		return false, err
	}
	return false, nil
}

func copyTree(src, dst string) error {
	return filepath.WalkDir(src, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(src, path)
		if err != nil {
			return err
		}
		if rel == "." {
			return nil
		}
		target := filepath.Join(dst, rel)
		info, err := d.Info()
		if err != nil {
			return err
		}
		if d.IsDir() {
			return os.MkdirAll(target, info.Mode().Perm())
		}
		return copyFile(path, target, info.Mode().Perm())
	})
}

func copyFile(src, dst string, mode os.FileMode) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return err
	}
	out, err := os.OpenFile(dst, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, mode)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		return err
	}
	return out.Close()
}
