package jm

import (
	"context"
	"crypto/tls"
	"net"
	"net/http"
	"net/url"
	"time"
)

// attemptBudget is how long one API host may stall before the client tries the next.
// A black-holed address in a naked connection should fail here, not after the
// whole 40s client timeout. The first uncached response can still be slow when
// every reachable host is far away; this only avoids waiting on a dead one.
const attemptBudget = 8 * time.Second

func newTransport(proxy *url.URL) *http.Transport {
	dialer := &net.Dialer{
		Timeout:   4 * time.Second,
		KeepAlive: 30 * time.Second,
	}
	return &http.Transport{
		Proxy: func(*http.Request) (*url.URL, error) {
			// Empty proxy is a direct connection. Environment proxies are ignored
			// so a leftover system proxy does not become mandatory.
			return proxy, nil
		},
		DialContext:           dialer.DialContext,
		ForceAttemptHTTP2:     true,
		MaxIdleConns:          64,
		MaxIdleConnsPerHost:   16,
		IdleConnTimeout:       90 * time.Second,
		TLSHandshakeTimeout:   5 * time.Second,
		ResponseHeaderTimeout: 8 * time.Second,
		ExpectContinueTimeout: 1 * time.Second,
		TLSClientConfig:       &tls.Config{MinVersion: tls.VersionTLS12},
	}
}

// SetProxy switches the client between a direct connection and an optional HTTP proxy.
// The cookie jar is kept. raw empty means direct.
func (c *Client) SetProxy(raw string) {
	proxy := proxyURL(raw)
	c.mu.Lock()
	defer c.mu.Unlock()
	c.http.Transport = newTransport(proxy)
	c.http.CloseIdleConnections()
}

func proxyURL(raw string) *url.URL {
	raw = trimProxy(raw)
	if raw == "" {
		return nil
	}
	u, err := url.Parse(raw)
	if err != nil || u.Host == "" || (u.Scheme != "http" && u.Scheme != "https") {
		return nil
	}
	return u
}

func trimProxy(raw string) string {
	for len(raw) > 0 && (raw[0] == ' ' || raw[0] == '\n' || raw[0] == '\t') {
		raw = raw[1:]
	}
	for len(raw) > 0 && (raw[len(raw)-1] == ' ' || raw[len(raw)-1] == '\n' || raw[len(raw)-1] == '\t') {
		raw = raw[:len(raw)-1]
	}
	return raw
}

func hostPort(origin string) string {
	u, err := url.Parse(origin)
	if err != nil || u.Host == "" {
		return ""
	}
	if u.Port() != "" {
		return u.Host
	}
	if u.Scheme == "http" {
		return u.Hostname() + ":80"
	}
	return u.Hostname() + ":443"
}

func dialTLS(ctx context.Context, origin string) error {
	addr := hostPort(origin)
	if addr == "" {
		return context.DeadlineExceeded
	}
	dialer := &net.Dialer{Timeout: 3 * time.Second, KeepAlive: 30 * time.Second}
	conn, err := dialer.DialContext(ctx, "tcp", addr)
	if err != nil {
		return err
	}
	host := addr
	if h, _, splitErr := net.SplitHostPort(addr); splitErr == nil {
		host = h
	}
	tlsConn := tls.Client(conn, &tls.Config{ServerName: host, MinVersion: tls.VersionTLS12})
	defer tlsConn.Close()
	return tlsConn.HandshakeContext(ctx)
}
