package jm

// Summary is a search hit or any compact album reference.
type Summary struct {
	ID          int64    `json:"id"`
	Title       string   `json:"title"`
	Author      string   `json:"author"`
	Description string   `json:"description,omitempty"`
	Tags        []string `json:"tags,omitempty"`
	Favorites   int      `json:"favorites"`
	PageCount   int      `json:"pageCount,omitempty"`
	Image       string   `json:"image,omitempty"`
	Downloaded  bool     `json:"downloaded,omitempty"`
}

// ChapterRef is one episode inside an album, before its pages are known.
type ChapterRef struct {
	ID    int64  `json:"id"`
	Name  string `json:"name"`
	Sort  int    `json:"sort"`
	Pages int    `json:"pages,omitempty"`
}

// Album is a full comic detail.
type Album struct {
	Summary
	Works        []string     `json:"works,omitempty"`
	Actors       []string     `json:"actors,omitempty"`
	Chapters     []ChapterRef `json:"chapters"`
	Related      []Summary    `json:"related,omitempty"`
	InlineImages []string     `json:"-"`
}

// ChapterDetail is the page list for one episode.
type ChapterDetail struct {
	ID      int64
	AlbumID int64
	Name    string
	Sort    int
	Images  []string
}

// SearchResult is one page of keyword search.
type SearchResult struct {
	Query  string    `json:"query"`
	Page   int       `json:"page"`
	Total  int       `json:"total"`
	Direct bool      `json:"direct"`
	Items  []Summary `json:"items"`
}
