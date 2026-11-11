package app

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/bingking148/JMComicReaderProject/engine/internal/library"
)

func (a *App) Storage() library.Storage {
	return library.Storage{
		LibraryBytes: library.DirSize(a.comics),
		CacheBytes:   a.Covers.Size(),
		ComicsDir:    a.comics,
		DataDir:      a.DataDir,
	}
}

// ImportPath copies albums from a folder, zip, or cbz into the library.
// A finished book already on the shelf is left untouched.
func (a *App) ImportPath(source string) (library.ImportReport, error) {
	source = strings.TrimSpace(source)
	if source == "" {
		return library.ImportReport{}, &StatusError{Code: 400, Msg: "请选择要导入的位置"}
	}
	abs, err := filepath.Abs(source)
	if err != nil {
		return library.ImportReport{}, &StatusError{Code: 400, Msg: "路径不正确"}
	}
	info, err := os.Stat(abs)
	if err != nil {
		return library.ImportReport{}, &StatusError{Code: 400, Msg: "找不到这个文件或文件夹"}
	}
	root := abs
	hintID := int64(0)
	hintTitle := ""
	if !info.IsDir() {
		if !library.IsArchive(abs) {
			return library.ImportReport{}, &StatusError{Code: 400, Msg: "只支持文件夹、zip 或 cbz"}
		}
		tmp, err := os.MkdirTemp(a.DataDir, "import-")
		if err != nil {
			return library.ImportReport{}, err
		}
		defer os.RemoveAll(tmp)
		if err := library.ExtractArchive(abs, tmp); err != nil {
			return library.ImportReport{}, &StatusError{Code: 400, Msg: err.Error()}
		}
		root = tmp
		if id, title, ok := library.ArchiveID(abs); ok {
			hintID, hintTitle = id, title
		}
	}
	albums, err := library.FindAlbums(root, hintID, hintTitle)
	if err != nil {
		return library.ImportReport{}, err
	}
	if len(albums) == 0 {
		return library.ImportReport{}, &StatusError{Code: 400, Msg: "这里没有可导入的漫画。需要 {编号}_{标题} 目录，或同样结构的 zip / cbz"}
	}
	if err := os.MkdirAll(a.comics, 0o755); err != nil {
		return library.ImportReport{}, err
	}
	var report library.ImportReport
	for _, album := range albums {
		item := a.importOne(album)
		switch item.Action {
		case "imported":
			report.Imported++
		case "merged":
			report.Merged++
		case "skipped":
			report.Skipped++
		default:
			report.Failed++
		}
		report.Items = append(report.Items, item)
	}
	n, err := a.Rescan()
	report.Rescanned = n
	if report.Items == nil {
		report.Items = []library.ImportItem{}
	}
	return report, err
}

func (a *App) importOne(album library.Located) library.ImportItem {
	item := library.ImportItem{ID: album.ID, Title: album.Title}
	if existing, err := a.Library.Get(album.ID); err == nil && existing.Status == "complete" {
		if st, statErr := os.Stat(existing.Dir); statErr == nil && st.IsDir() && library.PageCount(existing.Dir) > 0 {
			item.Action = "skipped"
			item.Detail = "已在书架，未覆盖"
			return item
		}
	}
	dest, ok := library.FindComicDir(a.comics, album.ID)
	if !ok {
		dest = filepath.Join(a.comics, fmt.Sprintf("%d_%s", album.ID, library.SafeName(album.Title)))
	}
	if library.SamePath(album.Dir, dest) {
		item.Action = "skipped"
		item.Detail = "已在当前目录"
		return item
	}
	if st, err := os.Stat(dest); err == nil && st.IsDir() {
		n, err := library.CopyMissing(album.Dir, dest)
		if err != nil {
			item.Action = "error"
			item.Detail = err.Error()
			return item
		}
		if n == 0 {
			item.Action = "skipped"
			item.Detail = "没有新的页面"
			return item
		}
		item.Action = "merged"
		item.Detail = fmt.Sprintf("补充了 %d 个文件", n)
		return item
	}
	if err := library.CopyNew(album.Dir, dest); err != nil {
		item.Action = "error"
		item.Detail = err.Error()
		return item
	}
	item.Action = "imported"
	item.Detail = "已导入"
	return item
}
