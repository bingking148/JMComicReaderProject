package library

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"unicode"
)

var imageExts = map[string]bool{
	".jpg": true, ".jpeg": true, ".png": true, ".webp": true, ".gif": true, ".bmp": true,
}

// SafeName makes a single path segment that is safe on Windows and Unix.
func SafeName(name string) string {
	var b strings.Builder
	for _, r := range name {
		switch r {
		case '<', '>', ':', '"', '|', '?', '*', '\\', '/', '[', ']', '(', ')':
			b.WriteByte('_')
		default:
			if r < 32 || unicode.IsControl(r) {
				continue
			}
			b.WriteRune(r)
		}
	}
	out := strings.Trim(b.String(), ". ")
	runes := []rune(out)
	if len(runes) > 80 {
		out = string(runes[:80])
		out = strings.TrimRight(out, ". ")
	}
	if out == "" {
		return "comic"
	}
	return out
}

// FindComicDir returns the album directory for id, if one exists.
func FindComicDir(root string, id int64) (string, bool) {
	prefix := strconv.FormatInt(id, 10) + "_"
	entries, err := os.ReadDir(root)
	if err != nil {
		return "", false
	}
	for _, e := range entries {
		if e.IsDir() && strings.HasPrefix(e.Name(), prefix) {
			return filepath.Join(root, e.Name()), true
		}
	}
	return "", false
}

// EnsureComicDir finds or creates the album directory.
func EnsureComicDir(root string, id int64, title string) (string, error) {
	if dir, ok := FindComicDir(root, id); ok {
		return dir, nil
	}
	if err := os.MkdirAll(root, 0o755); err != nil {
		return "", err
	}
	dir := filepath.Join(root, fmt.Sprintf("%d_%s", id, SafeName(title)))
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	return dir, nil
}

// PageReady reports whether a 1-based page index already has a decoded file.
func PageReady(dir string, index int) bool {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return false
	}
	prefix := fmt.Sprintf("%05d", index)
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		name := e.Name()
		stem := strings.TrimSuffix(name, filepath.Ext(name))
		if stem == prefix && imageExts[strings.ToLower(filepath.Ext(name))] {
			info, err := e.Info()
			return err == nil && info.Size() > 0
		}
	}
	return false
}

// ReaderChapter is one chapter ready for the reader.
type ReaderChapter struct {
	ID    string   `json:"id"`
	Name  string   `json:"name"`
	Pages []string `json:"pages"`
}

// ReaderDoc is the offline book the UI opens.
type ReaderDoc struct {
	ID       int64           `json:"id"`
	Title    string          `json:"title"`
	Chapters []ReaderChapter `json:"chapters"`
	Progress Progress        `json:"progress"`
	Mode     string          `json:"mode"`
	Fit      string          `json:"fit"`
	RTL      bool            `json:"rtl"`
}

// ScanComic reads chapter folders. It also understands the old Python layout
// where a single chapter's images sit directly in the album folder.
func ScanComic(dir string, info DiskInfo) []ReaderChapter {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil
	}
	subdirs := map[string]string{}
	var rootPages []string
	for _, e := range entries {
		name := e.Name()
		if e.IsDir() {
			subdirs[name] = filepath.Join(dir, name)
			continue
		}
		if isPageFile(name) {
			rootPages = append(rootPages, filepath.Join(dir, name))
		}
	}
	sortPages(rootPages)

	var chapters []ReaderChapter
	if len(info.Chapters) > 0 {
		for _, ch := range info.Chapters {
			id := strconv.FormatInt(ch.ID, 10)
			name := ch.Name
			if name == "" {
				name = fmt.Sprintf("第%d话", ch.Sort)
			}
			if sub, ok := subdirs[id]; ok {
				pages := listPages(sub)
				chapters = append(chapters, ReaderChapter{ID: id, Name: name, Pages: pages})
				delete(subdirs, id)
				continue
			}
			if len(info.Chapters) == 1 && len(rootPages) > 0 {
				chapters = append(chapters, ReaderChapter{ID: id, Name: name, Pages: rootPages})
				rootPages = nil
			}
		}
	}
	var extra []string
	for name := range subdirs {
		extra = append(extra, name)
	}
	sort.Slice(extra, func(i, j int) bool {
		ai, aerr := strconv.Atoi(extra[i])
		bi, berr := strconv.Atoi(extra[j])
		if aerr == nil && berr == nil {
			return ai < bi
		}
		return extra[i] < extra[j]
	})
	for i, name := range extra {
		pages := listPages(subdirs[name])
		if len(pages) == 0 {
			continue
		}
		chapters = append(chapters, ReaderChapter{
			ID:    name,
			Name:  fmt.Sprintf("第%d话", len(chapters)+i+1),
			Pages: pages,
		})
	}
	if len(chapters) == 0 && len(rootPages) > 0 {
		id := "1"
		if info.ID > 0 {
			id = strconv.FormatInt(info.ID, 10)
		}
		chapters = []ReaderChapter{{ID: id, Name: "第1话", Pages: rootPages}}
	}
	return chapters
}

func listPages(dir string) []string {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil
	}
	var pages []string
	for _, e := range entries {
		if e.IsDir() || !isPageFile(e.Name()) {
			continue
		}
		pages = append(pages, filepath.Join(dir, e.Name()))
	}
	sortPages(pages)
	return pages
}

func isPageFile(name string) bool {
	lower := strings.ToLower(name)
	if strings.HasPrefix(lower, "cover") || lower == "info.json" {
		return false
	}
	return imageExts[filepath.Ext(lower)]
}

func sortPages(pages []string) {
	sort.Slice(pages, func(i, j int) bool {
		return pageNumber(pages[i]) < pageNumber(pages[j])
	})
}

func pageNumber(p string) int {
	stem := strings.TrimSuffix(filepath.Base(p), filepath.Ext(p))
	n := 0
	for _, r := range stem {
		if r < '0' || r > '9' {
			continue
		}
		n = n*10 + int(r-'0')
	}
	if n == 0 {
		return 1 << 30
	}
	return n
}

// DirSize walks a tree.
func DirSize(root string) int64 {
	var total int64
	_ = filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return nil
		}
		info, err := d.Info()
		if err == nil {
			total += info.Size()
		}
		return nil
	})
	return total
}

// ParseAlbumID reads the leading integer from a "{id}_title" folder.
func ParseAlbumID(folderName string) (int64, bool) {
	i := strings.IndexByte(folderName, '_')
	if i <= 0 {
		return 0, false
	}
	n, err := strconv.ParseInt(folderName[:i], 10, 64)
	return n, err == nil && n > 0
}
