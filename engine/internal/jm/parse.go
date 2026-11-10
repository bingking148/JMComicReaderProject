package jm

import (
	"encoding/json"
	"fmt"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

var countPattern = regexp.MustCompile(`(\d+(?:\.\d+)?)(亿|万|k|m|b|w)?`)

var idPattern = regexp.MustCompile(`^(?i)(?:JM)?(\d+)$`)

// ParseJMID accepts "123456" and "JM123456".
func ParseJMID(query string) (int64, bool) {
	m := idPattern.FindStringSubmatch(strings.TrimSpace(query))
	if m == nil {
		return 0, false
	}
	n, err := strconv.ParseInt(m[1], 10, 64)
	if err != nil || n <= 0 {
		return 0, false
	}
	return n, true
}

// ParseCount understands plain numbers and the site's 万/k suffixes.
func ParseCount(v any) int {
	switch t := v.(type) {
	case nil:
		return 0
	case float64:
		return int(t)
	case int:
		return t
	case int64:
		return int(t)
	case json.Number:
		i, err := t.Int64()
		if err != nil {
			f, ferr := t.Float64()
			if ferr != nil {
				return 0
			}
			return int(f)
		}
		return int(i)
	default:
		return parseCountString(asString(v))
	}
}

func parseCountString(text string) int {
	text = strings.ToLower(strings.ReplaceAll(strings.TrimSpace(text), ",", ""))
	text = strings.ReplaceAll(text, " ", "")
	if text == "" {
		return 0
	}
	m := countPattern.FindStringSubmatch(text)
	if m == nil {
		return 0
	}
	n, err := strconv.ParseFloat(m[1], 64)
	if err != nil {
		return 0
	}
	mult := map[string]float64{
		"": 1, "w": 10_000, "k": 1_000, "m": 1_000_000, "b": 1_000_000_000,
		"万": 10_000, "亿": 100_000_000,
	}[m[2]]
	if mult == 0 {
		mult = 1
	}
	return int(n * mult)
}

func asString(v any) string {
	switch t := v.(type) {
	case nil:
		return ""
	case string:
		return strings.TrimSpace(t)
	case float64:
		if t == float64(int64(t)) {
			return strconv.FormatInt(int64(t), 10)
		}
		return strconv.FormatFloat(t, 'f', -1, 64)
	case json.Number:
		return t.String()
	default:
		return strings.TrimSpace(fmt.Sprint(t))
	}
}

func asInt64(v any) int64 {
	switch t := v.(type) {
	case nil:
		return 0
	case float64:
		return int64(t)
	case int:
		return int64(t)
	case int64:
		return t
	case json.Number:
		i, err := t.Int64()
		if err != nil {
			return 0
		}
		return i
	case string:
		s := strings.TrimSpace(t)
		s = strings.TrimPrefix(strings.ToUpper(s), "JM")
		n, _ := strconv.ParseInt(s, 10, 64)
		return n
	default:
		n, _ := strconv.ParseInt(asString(v), 10, 64)
		return n
	}
}

func asMap(v any) map[string]any {
	m, _ := v.(map[string]any)
	return m
}

func stringList(v any) []string {
	switch t := v.(type) {
	case nil:
		return nil
	case string:
		return splitLoose(t)
	case []any:
		var out []string
		for _, item := range t {
			s := asString(item)
			if s != "" {
				out = append(out, s)
			}
		}
		return out
	default:
		s := asString(v)
		if s == "" {
			return nil
		}
		return []string{s}
	}
}

func authorsOf(v any) string {
	switch t := v.(type) {
	case nil:
		return ""
	case string:
		return strings.TrimSpace(t)
	case []any:
		var parts []string
		for _, item := range t {
			s := asString(item)
			if s != "" {
				parts = append(parts, s)
			}
		}
		return strings.Join(parts, " / ")
	default:
		return asString(v)
	}
}

func splitLoose(s string) []string {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil
	}
	var parts []string
	if strings.Contains(s, ",") {
		parts = strings.Split(s, ",")
	} else {
		parts = strings.Fields(s)
	}
	var out []string
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}

func categoryTitle(m map[string]any) string {
	cat := asMap(m["category"])
	if cat == nil {
		return ""
	}
	return asString(cat["title"])
}

// ParseAlbum decodes a decrypted /album body.
func ParseAlbum(raw []byte) (Album, error) {
	var m map[string]any
	if err := json.Unmarshal(raw, &m); err != nil {
		return Album{}, fmt.Errorf("专辑数据无法解析: %w", err)
	}
	if len(m) == 0 || asString(m["name"]) == "" && asInt64(m["id"]) == 0 {
		return Album{}, ErrNotFound
	}
	album := Album{
		Summary: Summary{
			ID:          asInt64(m["id"]),
			Title:       asString(m["name"]),
			Author:      authorsOf(m["author"]),
			Description: asString(m["description"]),
			Tags:        stringList(m["tags"]),
			Favorites:   ParseCount(m["likes"]),
		},
		Works:        stringList(m["works"]),
		Actors:       stringList(m["actors"]),
		InlineImages: stringList(m["images"]),
	}
	if album.Title == "" {
		album.Title = fmt.Sprintf("JM-%d", album.ID)
	}
	if album.Author == "" {
		album.Author = "未知作者"
	}
	album.Chapters = parseChapters(m["series"], album.ID, album.Title)
	if len(album.Chapters) == 1 && len(album.InlineImages) > 0 {
		album.PageCount = len(album.InlineImages)
		album.Chapters[0].Pages = len(album.InlineImages)
	}
	for _, item := range asSlice(m["related_list"]) {
		if s, ok := parseSummary(asMap(item)); ok {
			album.Related = append(album.Related, s)
		}
	}
	if album.ID <= 0 {
		return Album{}, ErrNotFound
	}
	return album, nil
}

func parseChapters(v any, albumID int64, albumTitle string) []ChapterRef {
	var chapters []ChapterRef
	seen := map[int]bool{}
	for _, item := range asSlice(v) {
		m := asMap(item)
		if m == nil {
			continue
		}
		ch := ChapterRef{
			ID:   asInt64(m["id"]),
			Name: asString(m["name"]),
			Sort: int(asInt64(m["sort"])),
		}
		if ch.ID <= 0 {
			continue
		}
		if ch.Sort <= 0 {
			ch.Sort = len(chapters) + 1
		}
		if seen[ch.Sort] {
			continue
		}
		seen[ch.Sort] = true
		if ch.Name == "" {
			ch.Name = fmt.Sprintf("第%d话", ch.Sort)
		}
		chapters = append(chapters, ch)
	}
	sort.SliceStable(chapters, func(i, j int) bool {
		return chapters[i].Sort < chapters[j].Sort
	})
	if len(chapters) == 0 {
		name := albumTitle
		if name == "" {
			name = "第1话"
		}
		chapters = []ChapterRef{{ID: albumID, Name: name, Sort: 1}}
	}
	return chapters
}

// ParseChapter decodes a decrypted /chapter body.
func ParseChapter(raw []byte) (ChapterDetail, error) {
	var m map[string]any
	if err := json.Unmarshal(raw, &m); err != nil {
		return ChapterDetail{}, err
	}
	ch := ChapterDetail{
		ID:      asInt64(m["id"]),
		AlbumID: asInt64(m["series_id"]),
		Name:    asString(m["name"]),
		Sort:    int(asInt64(m["sort"])),
		Images:  stringList(m["images"]),
	}
	if ch.ID <= 0 {
		return ChapterDetail{}, ErrNotFound
	}
	if ch.Sort <= 0 {
		for _, item := range asSlice(m["series"]) {
			sm := asMap(item)
			if asInt64(sm["id"]) == ch.ID {
				ch.Sort = int(asInt64(sm["sort"]))
				if ch.Name == "" {
					ch.Name = asString(sm["name"])
				}
				break
			}
		}
	}
	if ch.Sort <= 0 {
		ch.Sort = 1
	}
	return ch, nil
}

// ParseSearch decodes a decrypted /search body.
func ParseSearch(raw []byte) (SearchResult, error) {
	var m map[string]any
	if err := json.Unmarshal(raw, &m); err != nil {
		return SearchResult{}, err
	}
	res := SearchResult{Total: ParseCount(m["total"])}
	if id := asInt64(m["redirect_aid"]); id > 0 {
		res.Direct = true
		res.Total = 1
		res.Items = []Summary{{ID: id, Title: fmt.Sprintf("JM-%d", id)}}
		return res, nil
	}
	for _, item := range asSlice(m["content"]) {
		if s, ok := parseSummary(asMap(item)); ok {
			res.Items = append(res.Items, s)
		}
	}
	if res.Items == nil {
		res.Items = []Summary{}
	}
	return res, nil
}

func parseSummary(m map[string]any) (Summary, bool) {
	if m == nil {
		return Summary{}, false
	}
	s := Summary{
		ID:          asInt64(m["id"]),
		Title:       asString(m["name"]),
		Author:      authorsOf(m["author"]),
		Description: asString(m["description"]),
		Tags:        stringList(m["tags"]),
		Favorites:   ParseCount(firstPresent(m, "favorites", "likes", "like")),
		Image:       asString(m["image"]),
	}
	if s.Title == "" {
		s.Title = asString(m["title"])
	}
	if len(s.Tags) == 0 {
		if cat := categoryTitle(m); cat != "" {
			s.Tags = []string{cat}
		}
	}
	if s.ID <= 0 {
		return Summary{}, false
	}
	if s.Title == "" {
		s.Title = fmt.Sprintf("JM-%d", s.ID)
	}
	if s.Author == "" {
		s.Author = "未知作者"
	}
	if len(s.Description) > 180 {
		s.Description = string([]rune(s.Description)[:180])
	}
	return s, true
}

func firstPresent(m map[string]any, keys ...string) any {
	for _, k := range keys {
		if v, ok := m[k]; ok && v != nil && asString(v) != "" {
			return v
		}
	}
	return nil
}

func asSlice(v any) []any {
	s, _ := v.([]any)
	return s
}
