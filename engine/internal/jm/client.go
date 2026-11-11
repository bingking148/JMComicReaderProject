package jm

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/cookiejar"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	// Secrets and the app version track the current mobile client.
	TokenSecret       = "185Hcomic3PAPP7R"
	ScrambleSecret    = "18comicAPPContent"
	DataSecret        = "185Hcomic3PAPP7R"
	DomainSecret      = "diosfjckwpqpdfjkvnqQjsik"
	DefaultAppVersion = "2.1.12"
	FallbackScramble  = 220980

	userAgent = "Mozilla/5.0 (Linux; Android 9; V1938CT Build/PQ3A.190705.11211812; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/91.0.4472.114 Safari/537.36"
)

// DomainServers publish the current API host list. The body is AES encrypted.
var DomainServers = []string{
	"https://rup4a04-c01.tos-ap-southeast-1.bytepluses.com/newsvr-2025.txt",
	"https://rup4a04-c02.tos-cn-hongkong.bytepluses.com/newsvr-2025.txt",
	"https://rup4a04-c03.tos-cn-beijing.bytepluses.com.cn/newsvr-2025.txt",
}

var scramblePattern = regexp.MustCompile(`var scramble_id\s*=\s*(\d+)\s*;`)

// Client talks to the mobile JSON API and the image CDN.
type Client struct {
	http *http.Client

	mu           sync.Mutex
	warmMu       sync.Mutex
	apiDomains   []string
	imageDomains []string
	version      string
	retry        int
	sticky       int
	warm         bool
	referer      string
}

func NewClient(apiDomains, imageDomains []string, version string, retry int) *Client {
	jar, _ := cookiejar.New(nil)
	if version == "" {
		version = DefaultAppVersion
	}
	if retry < 1 {
		retry = 3
	}
	c := &Client{
		http: &http.Client{
			Jar:     jar,
			Timeout: 40 * time.Second,
			Transport: &http.Transport{
				Proxy:               http.ProxyFromEnvironment,
				MaxIdleConns:        32,
				MaxIdleConnsPerHost: 8,
				IdleConnTimeout:     90 * time.Second,
				TLSHandshakeTimeout: 12 * time.Second,
			},
		},
		version: version,
		retry:   retry,
	}
	c.SetAPIDomains(apiDomains)
	c.SetImageDomains(imageDomains)
	return c
}

func (c *Client) SetAPIDomains(domains []string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.apiDomains = normalizeAll(domains)
	if len(c.apiDomains) > 0 {
		c.referer = c.apiDomains[0] + "/"
	}
}

func (c *Client) SetImageDomains(domains []string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.imageDomains = normalizeAll(domains)
}

func (c *Client) SetRetry(n int) {
	if n < 1 {
		n = 1
	}
	c.mu.Lock()
	c.retry = n
	c.mu.Unlock()
}

func (c *Client) Version() string {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.version
}

func (c *Client) APIDomains() []string {
	c.mu.Lock()
	defer c.mu.Unlock()
	out := make([]string, len(c.apiDomains))
	copy(out, c.apiDomains)
	return out
}

// Warmup fetches /setting so the cookie jar is populated and the app version
// can follow the site when it moves ahead of the built-in value.
func (c *Client) Warmup(ctx context.Context) error {
	c.warmMu.Lock()
	defer c.warmMu.Unlock()
	c.mu.Lock()
	if c.warm {
		c.mu.Unlock()
		return nil
	}
	c.mu.Unlock()
	body, err := c.call(ctx, "/setting", false)
	if err != nil {
		return err
	}
	var payload map[string]any
	_ = json.Unmarshal(body, &payload)
	if ver := asString(payload["version"]); ver != "" && versionLess(c.Version(), ver) {
		c.mu.Lock()
		c.version = ver
		c.mu.Unlock()
	}
	if host := asString(payload["img_host"]); host != "" {
		c.prependImage(host)
	}
	c.mu.Lock()
	c.warm = true
	c.mu.Unlock()
	return nil
}

func (c *Client) prependImage(origin string) {
	origin = NormalizeOrigin(origin)
	if origin == "" {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	next := []string{origin}
	for _, d := range c.imageDomains {
		if d != origin {
			next = append(next, d)
		}
	}
	c.imageDomains = next
}

// RefreshDomains reads the published API host list.
func (c *Client) RefreshDomains(ctx context.Context) ([]string, error) {
	var last error
	for _, server := range DomainServers {
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, server, nil)
		if err != nil {
			last = err
			continue
		}
		req.Header.Set("User-Agent", userAgent)
		resp, err := c.http.Do(req)
		if err != nil {
			last = err
			continue
		}
		body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
		resp.Body.Close()
		if err != nil || resp.StatusCode >= 400 {
			last = fmt.Errorf("域名服务 %s", resp.Status)
			continue
		}
		text := stripNonASCIIPrefix(string(body))
		plain, err := Decrypt(text, "", DomainSecret)
		if err != nil {
			last = err
			continue
		}
		var payload struct {
			Server []string `json:"Server"`
		}
		if err := json.Unmarshal(plain, &payload); err != nil {
			last = err
			continue
		}
		if len(payload.Server) == 0 {
			last = fmt.Errorf("域名列表为空")
			continue
		}
		return payload.Server, nil
	}
	if last == nil {
		last = fmt.Errorf("没有可用的域名服务")
	}
	return nil, last
}

func (c *Client) Search(ctx context.Context, query string, page int) (SearchResult, error) {
	return c.SearchOrdered(ctx, query, page, "mr", "a")
}

// SearchOrdered is the mobile search. orderBy is mr/mv/mp/tf and timeRange is t/w/m/a.
// The mobile search API does not accept category.
func (c *Client) SearchOrdered(ctx context.Context, query string, page int, orderBy, timeRange string) (SearchResult, error) {
	if err := c.Warmup(ctx); err != nil {
		// Cookies help, but a failed warmup should not block the search itself.
	}
	if page < 1 {
		page = 1
	}
	q := url.Values{}
	q.Set("main_tag", "0")
	q.Set("search_query", query)
	q.Set("page", strconv.Itoa(page))
	q.Set("o", NormalizeOrder(orderBy))
	q.Set("t", NormalizeTime(timeRange))
	body, err := c.call(ctx, "/search?"+q.Encode(), false)
	if err != nil {
		return SearchResult{}, err
	}
	res, err := ParseSearch(body)
	if err != nil {
		return SearchResult{}, err
	}
	if res.Direct && len(res.Items) == 1 && res.Items[0].Title == fmt.Sprintf("JM-%d", res.Items[0].ID) {
		album, aerr := c.Album(ctx, res.Items[0].ID)
		if aerr == nil {
			res.Items = []Summary{album.Summary}
		}
	}
	return res, nil
}

// Browse lists a category shelf. Time is folded into the order code, matching
// the mobile categories/filter API: mr, tf, mv_t, mv_w, mv_m.
func (c *Client) Browse(ctx context.Context, page int, category, orderBy, timeRange string) (SearchResult, error) {
	_ = c.Warmup(ctx)
	if page < 1 {
		page = 1
	}
	q := url.Values{}
	q.Set("page", strconv.Itoa(page))
	q.Set("order", "")
	q.Set("c", NormalizeCategory(category))
	q.Set("o", FilterOrder(orderBy, timeRange))
	body, err := c.call(ctx, "/categories/filter?"+q.Encode(), false)
	if err != nil {
		return SearchResult{}, err
	}
	return ParseSearch(body)
}

func (c *Client) Album(ctx context.Context, id int64) (Album, error) {
	_ = c.Warmup(ctx)
	body, err := c.call(ctx, "/album?id="+strconv.FormatInt(id, 10), false)
	if err != nil {
		return Album{}, err
	}
	return ParseAlbum(body)
}

func (c *Client) Chapter(ctx context.Context, photoID int64) (ChapterDetail, error) {
	_ = c.Warmup(ctx)
	body, err := c.call(ctx, "/chapter?id="+strconv.FormatInt(photoID, 10), false)
	if err != nil {
		return ChapterDetail{}, err
	}
	return ParseChapter(body)
}

func (c *Client) ScrambleID(ctx context.Context, photoID int64) (int, error) {
	q := url.Values{}
	q.Set("id", strconv.FormatInt(photoID, 10))
	q.Set("mode", "vertical")
	q.Set("page", "0")
	q.Set("app_img_shunt", "1")
	q.Set("express", "off")
	q.Set("v", strconv.FormatInt(time.Now().Unix(), 10))
	body, err := c.call(ctx, "/chapter_view_template?"+q.Encode(), true)
	if err != nil {
		return FallbackScramble, err
	}
	m := scramblePattern.FindSubmatch(body)
	if m == nil {
		return FallbackScramble, nil
	}
	n, err := strconv.Atoi(string(m[1]))
	if err != nil || n <= 0 {
		return FallbackScramble, nil
	}
	return n, nil
}

func (c *Client) FetchImage(ctx context.Context, photoID int64, name string) ([]byte, error) {
	return c.fetchAsset(ctx, fmt.Sprintf("/media/photos/%d/%s", photoID, url.PathEscape(name)))
}

func (c *Client) FetchCover(ctx context.Context, albumID int64) ([]byte, error) {
	paths := []string{
		fmt.Sprintf("/media/albums/%d.jpg", albumID),
		fmt.Sprintf("/media/albums/%d_3x4.jpg", albumID),
		fmt.Sprintf("/media/albums/%d.webp", albumID),
	}
	var last error
	for _, p := range paths {
		b, err := c.fetchAsset(ctx, p)
		if err == nil {
			return b, nil
		}
		last = err
	}
	if last == nil {
		last = fmt.Errorf("没有封面")
	}
	return nil, last
}

func (c *Client) fetchAsset(ctx context.Context, path string) ([]byte, error) {
	domains := c.snapshotImages()
	if len(domains) == 0 {
		return nil, fmt.Errorf("没有图片域名")
	}
	var last error
	for _, origin := range domains {
		for _, withV := range []bool{false, true} {
			u := origin + path
			if withV {
				u += "?v=" + strconv.FormatInt(time.Now().Unix(), 10)
			}
			body, err := c.fetchBinary(ctx, u)
			if err == nil && looksLikeImage(body) {
				return body, nil
			}
			if err != nil {
				last = err
			} else {
				last = fmt.Errorf("响应不是图片")
			}
		}
	}
	if last == nil {
		last = fmt.Errorf("下载失败")
	}
	return nil, last
}

func (c *Client) fetchBinary(ctx context.Context, rawURL string) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, rawURL, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", userAgent)
	req.Header.Set("Accept", "image/avif,image/webp,image/apng,image/*,*/*;q=0.8")
	req.Header.Set("X-Requested-With", "com.jiaohua_browser")
	req.Header.Set("Accept-Language", "zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7")
	c.mu.Lock()
	req.Header.Set("Referer", c.referer)
	c.mu.Unlock()
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 40<<20))
	if err != nil {
		return nil, err
	}
	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	return body, nil
}

func (c *Client) call(ctx context.Context, path string, scramble bool) ([]byte, error) {
	domains, retry, version, sticky := c.snapshotAPI()
	if len(domains) == 0 {
		return nil, fmt.Errorf("没有 API 域名")
	}
	secret := TokenSecret
	if scramble {
		secret = ScrambleSecret
	}
	var last error
	for i := 0; i < retry; i++ {
		origin := domains[(sticky+i)%len(domains)]
		body, err := c.once(ctx, origin, path, version, secret, scramble)
		if err == nil {
			c.mu.Lock()
			c.sticky = (sticky + i) % len(domains)
			c.referer = origin + "/"
			c.mu.Unlock()
			return body, nil
		}
		last = err
		if err == ErrNotFound {
			return nil, err
		}
	}
	if last == nil {
		last = fmt.Errorf("请求失败")
	}
	return nil, last
}

func (c *Client) once(ctx context.Context, origin, path, version, secret string, scramble bool) ([]byte, error) {
	ts := strconv.FormatInt(time.Now().Unix(), 10)
	token, tokenParam := Token(ts, version, secret)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, origin+path, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", userAgent)
	req.Header.Set("token", token)
	req.Header.Set("tokenparam", tokenParam)
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	limit := int64(8 << 20)
	if scramble {
		limit = 2 << 20
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, limit))
	if err != nil {
		return nil, err
	}
	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	if scramble {
		return body, nil
	}
	plain, err := decodeEnvelope(body, ts)
	if err != nil {
		return nil, err
	}
	if isMissing(plain) {
		return nil, ErrNotFound
	}
	return plain, nil
}

func decodeEnvelope(body []byte, ts string) ([]byte, error) {
	var env struct {
		Code int    `json:"code"`
		Data string `json:"data"`
		Msg  string `json:"msg"`
	}
	if err := json.Unmarshal(body, &env); err != nil {
		return nil, fmt.Errorf("响应不是 JSON")
	}
	if env.Code != 200 {
		if env.Msg != "" {
			return nil, fmt.Errorf("%s", env.Msg)
		}
		return nil, fmt.Errorf("接口返回 %d", env.Code)
	}
	if env.Data == "" {
		return []byte("null"), nil
	}
	return Decrypt(env.Data, ts, DataSecret)
}

func isMissing(plain []byte) bool {
	s := strings.TrimSpace(string(plain))
	return s == "" || s == "null" || s == "[]" || s == "{}"
}

func (c *Client) snapshotAPI() (domains []string, retry int, version string, sticky int) {
	c.mu.Lock()
	defer c.mu.Unlock()
	domains = append([]string{}, c.apiDomains...)
	return domains, c.retry, c.version, c.sticky
}

func (c *Client) snapshotImages() []string {
	c.mu.Lock()
	defer c.mu.Unlock()
	return append([]string{}, c.imageDomains...)
}

// NormalizeOrigin accepts a host or a full URL and returns an origin.
func NormalizeOrigin(raw string) string {
	raw = strings.TrimSpace(raw)
	raw = strings.TrimRight(raw, "/")
	if raw == "" {
		return ""
	}
	if !strings.Contains(raw, "://") {
		raw = "https://" + raw
	}
	u, err := url.Parse(raw)
	if err != nil || u.Host == "" {
		return ""
	}
	return u.Scheme + "://" + u.Host
}

func normalizeAll(in []string) []string {
	var out []string
	seen := map[string]bool{}
	for _, item := range in {
		n := NormalizeOrigin(item)
		if n == "" || seen[n] {
			continue
		}
		seen[n] = true
		out = append(out, n)
	}
	return out
}

func stripNonASCIIPrefix(s string) string {
	for i, r := range s {
		if r < 128 {
			return strings.TrimSpace(s[i:])
		}
	}
	return ""
}

func versionLess(a, b string) bool {
	ap := splitVer(a)
	bp := splitVer(b)
	n := len(ap)
	if len(bp) > n {
		n = len(bp)
	}
	for i := 0; i < n; i++ {
		av, bv := 0, 0
		if i < len(ap) {
			av = ap[i]
		}
		if i < len(bp) {
			bv = bp[i]
		}
		if av < bv {
			return true
		}
		if av > bv {
			return false
		}
	}
	return false
}

func splitVer(s string) []int {
	parts := strings.Split(s, ".")
	out := make([]int, 0, len(parts))
	for _, p := range parts {
		n, _ := strconv.Atoi(p)
		out = append(out, n)
	}
	return out
}

func looksLikeImage(b []byte) bool {
	if len(b) < 12 {
		return false
	}
	if b[0] == 0xFF && b[1] == 0xD8 {
		return true
	}
	if b[0] == 0x89 && b[1] == 'P' && b[2] == 'N' && b[3] == 'G' {
		return true
	}
	if b[0] == 'G' && b[1] == 'I' && b[2] == 'F' && b[3] == '8' {
		return true
	}
	if string(b[0:4]) == "RIFF" && string(b[8:12]) == "WEBP" {
		return true
	}
	return false
}
