package library

import (
	"archive/zip"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

const (
	maxArchiveFiles = 20000
	maxArchiveBytes = 8 << 30
)

// Located is one album folder the importer can copy.
type Located struct {
	Dir   string
	ID    int64
	Title string
	Pages int
}

// ImportItem is one album's result. Action is imported, merged, skipped, or error.
type ImportItem struct {
	ID     int64  `json:"id"`
	Title  string `json:"title"`
	Action string `json:"action"`
	Detail string `json:"detail"`
}

// Storage splits downloaded comics from disposable cover cache.
type Storage struct {
	LibraryBytes int64  `json:"libraryBytes"`
	CacheBytes   int64  `json:"cacheBytes"`
	ComicsDir    string `json:"comicsDir"`
	DataDir      string `json:"dataDir"`
}

// ImportReport is the summary shown after an import.
type ImportReport struct {
	Imported  int          `json:"imported"`
	Merged    int          `json:"merged"`
	Skipped   int          `json:"skipped"`
	Failed    int          `json:"failed"`
	Rescanned int          `json:"rescanned"`
	Items     []ImportItem `json:"items"`
}

// FindAlbums lists album folders under root. hintID is used only when root
// itself is a pile of pages without a numbered folder name, as with a cbz
// named "123_title.cbz".
func FindAlbums(root string, hintID int64, hintTitle string) ([]Located, error) {
	root, err := filepath.Abs(root)
	if err != nil {
		return nil, err
	}
	info, err := os.Stat(root)
	if err != nil {
		return nil, err
	}
	if !info.IsDir() {
		return nil, fmt.Errorf("不是文件夹")
	}
	if album, ok := inspect(root, hintID, hintTitle); ok {
		return []Located{album}, nil
	}
	entries, err := os.ReadDir(root)
	if err != nil {
		return nil, err
	}
	var out []Located
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		name := e.Name()
		path := filepath.Join(root, name)
		if strings.EqualFold(name, "cache") {
			continue
		}
		if strings.EqualFold(name, "comics") {
			nested, err := FindAlbums(path, 0, "")
			if err != nil {
				return nil, err
			}
			out = append(out, nested...)
			continue
		}
		if album, ok := inspect(path, 0, ""); ok {
			out = append(out, album)
		}
	}
	return out, nil
}

func inspect(dir string, hintID int64, hintTitle string) (Located, bool) {
	info := ReadInfo(dir)
	id := info.ID
	title := strings.TrimSpace(info.Title)
	if id == 0 {
		if n, ok := ParseAlbumID(filepath.Base(dir)); ok {
			id = n
		}
	}
	if title == "" {
		if _, ok := ParseAlbumID(filepath.Base(dir)); ok {
			title = strings.TrimPrefix(filepath.Base(dir), fmt.Sprintf("%d_", id))
		}
	}
	pages := countPages(dir, info)
	if id == 0 && hintID > 0 && pages > 0 {
		id = hintID
		if title == "" {
			title = hintTitle
		}
	}
	if id == 0 || pages == 0 {
		return Located{}, false
	}
	if title == "" {
		title = fmt.Sprintf("JM-%d", id)
	}
	return Located{Dir: dir, ID: id, Title: title, Pages: pages}, true
}

func countPages(dir string, info DiskInfo) int {
	n := 0
	for _, ch := range ScanComic(dir, info) {
		n += len(ch.Pages)
	}
	return n
}

// PageCount is the number of readable images under an album folder.
func PageCount(dir string) int {
	return countPages(dir, ReadInfo(dir))
}

// IsArchive reports zip and cbz files. cbz is a zip with a different suffix.
func IsArchive(path string) bool {
	switch strings.ToLower(filepath.Ext(path)) {
	case ".zip", ".cbz":
		return true
	default:
		return false
	}
}

// ArchiveID reads "{id}_{title}" from a zip or cbz file name.
func ArchiveID(path string) (int64, string, bool) {
	base := strings.TrimSuffix(filepath.Base(path), filepath.Ext(path))
	id, ok := ParseAlbumID(base)
	if !ok {
		return 0, "", false
	}
	title := strings.TrimPrefix(base, fmt.Sprintf("%d_", id))
	return id, title, true
}

// ExtractArchive unpacks a zip or cbz into dest. Paths that escape dest are rejected.
func ExtractArchive(src, dest string) error {
	reader, err := zip.OpenReader(src)
	if err != nil {
		return fmt.Errorf("打不开压缩包")
	}
	defer reader.Close()
	if len(reader.File) > maxArchiveFiles {
		return fmt.Errorf("压缩包里的文件太多")
	}
	var total int64
	for _, file := range reader.File {
		target, err := safeJoin(dest, file.Name)
		if err != nil {
			return err
		}
		if file.FileInfo().IsDir() {
			if err := os.MkdirAll(target, 0o755); err != nil {
				return err
			}
			continue
		}
		if file.FileInfo().Mode()&os.ModeSymlink != 0 {
			return fmt.Errorf("压缩包含有不支持的链接")
		}
		total += int64(file.UncompressedSize64)
		if total > maxArchiveBytes {
			return fmt.Errorf("压缩包过大")
		}
		if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
			return err
		}
		if err := extractFile(file, target); err != nil {
			return err
		}
	}
	return nil
}

func extractFile(file *zip.File, target string) error {
	in, err := file.Open()
	if err != nil {
		return err
	}
	defer in.Close()
	tmp := target + ".part"
	out, err := os.OpenFile(tmp, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o644)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		_ = os.Remove(tmp)
		return err
	}
	if err := out.Close(); err != nil {
		_ = os.Remove(tmp)
		return err
	}
	return os.Rename(tmp, target)
}

func safeJoin(root, name string) (string, error) {
	name = strings.ReplaceAll(name, "\\", "/")
	if name == "" || strings.HasPrefix(name, "/") || strings.Contains(name, "\x00") {
		return "", fmt.Errorf("压缩包路径不安全")
	}
	clean := filepath.Clean(filepath.FromSlash(name))
	if clean == ".." || strings.HasPrefix(clean, ".."+string(os.PathSeparator)) {
		return "", fmt.Errorf("压缩包路径不安全")
	}
	full := filepath.Join(root, clean)
	rel, err := filepath.Rel(root, full)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(os.PathSeparator)) {
		return "", fmt.Errorf("压缩包路径不安全")
	}
	return full, nil
}

// SamePath reports whether two paths name the same directory.
func SamePath(a, b string) bool {
	aa, errA := filepath.Abs(a)
	bb, errB := filepath.Abs(b)
	if errA != nil || errB != nil {
		return filepath.Clean(a) == filepath.Clean(b)
	}
	return filepath.Clean(aa) == filepath.Clean(bb)
}

// CopyNew copies an album folder into an empty destination.
func CopyNew(src, dst string) error {
	if err := rejectNested(src, dst); err != nil {
		return err
	}
	_, err := copyWalk(src, dst, false)
	return err
}

// CopyMissing copies files that are not already present and non-empty.
func CopyMissing(src, dst string) (int, error) {
	if err := rejectNested(src, dst); err != nil {
		return 0, err
	}
	return copyWalk(src, dst, true)
}

func rejectNested(src, dst string) error {
	rel, err := filepath.Rel(src, dst)
	if err != nil {
		return err
	}
	if rel != "." && !strings.HasPrefix(rel, "..") {
		return fmt.Errorf("不能把目录导入到它自己里面")
	}
	return nil
}

func copyWalk(src, dst string, onlyMissing bool) (int, error) {
	copied := 0
	err := filepath.WalkDir(src, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.Type()&os.ModeSymlink != 0 {
			return nil
		}
		rel, err := filepath.Rel(src, path)
		if err != nil {
			return err
		}
		if rel == "." {
			return os.MkdirAll(dst, 0o755)
		}
		target := filepath.Join(dst, rel)
		if d.IsDir() {
			return os.MkdirAll(target, 0o755)
		}
		if !d.Type().IsRegular() {
			return nil
		}
		if onlyMissing {
			if info, err := os.Stat(target); err == nil && info.Size() > 0 {
				return nil
			}
		}
		if err := copyFile(path, target); err != nil {
			return err
		}
		copied++
		return nil
	})
	return copied, err
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return err
	}
	tmp := dst + ".part"
	out, err := os.OpenFile(tmp, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o644)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		_ = os.Remove(tmp)
		return err
	}
	if err := out.Close(); err != nil {
		_ = os.Remove(tmp)
		return err
	}
	return os.Rename(tmp, dst)
}
