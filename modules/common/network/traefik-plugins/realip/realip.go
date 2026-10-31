// Package realip sets the client IP from Cloudflare's CF-Connecting-IP, but
// only for requests from trusted peers (cloudflared on loopback). From any
// other peer the header is dropped, so a container cannot claim a client IP.
package realip

import (
	"context"
	"fmt"
	"net"
	"net/http"
)

// Config is the middleware's dynamic configuration.
type Config struct {
	TrustedIPs []string `json:"trustedIPs"`
}

// CreateConfig returns the default (empty) configuration.
func CreateConfig() *Config {
	return &Config{}
}

type realIP struct {
	next    http.Handler
	trusted []*net.IPNet
}

// New builds the middleware; an invalid CIDR is an error.
func New(_ context.Context, next http.Handler, cfg *Config, _ string) (http.Handler, error) {
	r := &realIP{next: next}
	for _, cidr := range cfg.TrustedIPs {
		_, n, err := net.ParseCIDR(cidr)
		if err != nil {
			return nil, fmt.Errorf("realip: trustedIPs: %w", err)
		}
		r.trusted = append(r.trusted, n)
	}
	return r, nil
}

func (r *realIP) ServeHTTP(w http.ResponseWriter, req *http.Request) {
	if !r.fromTrusted(req.RemoteAddr) {
		req.Header.Del("CF-Connecting-IP")
	} else if ip := net.ParseIP(req.Header.Get("CF-Connecting-IP")); ip != nil {
		req.Header.Set("X-Forwarded-For", ip.String())
		req.Header.Set("X-Real-Ip", ip.String())
	}
	r.next.ServeHTTP(w, req)
}

func (r *realIP) fromTrusted(remoteAddr string) bool {
	host, _, err := net.SplitHostPort(remoteAddr)
	if err != nil {
		return false
	}
	ip := net.ParseIP(host)
	if ip == nil {
		return false
	}
	for _, n := range r.trusted {
		if n.Contains(ip) {
			return true
		}
	}
	return false
}
