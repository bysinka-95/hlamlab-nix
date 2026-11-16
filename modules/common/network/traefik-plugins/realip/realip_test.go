package realip

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

func serve(t *testing.T, remoteAddr string, headers map[string]string) http.Header {
	t.Helper()
	cfg := CreateConfig()
	cfg.TrustedIPs = []string{"127.0.0.1/32", "::1/128"}
	var got http.Header
	h, err := New(context.Background(), http.HandlerFunc(func(_ http.ResponseWriter, r *http.Request) { got = r.Header.Clone() }), cfg, "real-ip")
	if err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest(http.MethodGet, "https://auth.example.com/", nil)
	req.RemoteAddr = remoteAddr
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	h.ServeHTTP(httptest.NewRecorder(), req)
	return got
}

func TestLoopbackPeerTakesCFConnectingIP(t *testing.T) {
	for _, peer := range []string{"127.0.0.1:40000", "[::1]:40000"} {
		got := serve(t, peer, map[string]string{"CF-Connecting-IP": "203.0.113.7", "X-Forwarded-For": "1.2.3.4, 203.0.113.7"})
		if got.Get("X-Forwarded-For") != "203.0.113.7" || got.Get("X-Real-Ip") != "203.0.113.7" {
			t.Errorf("peer %s: XFF=%q X-Real-Ip=%q", peer, got.Get("X-Forwarded-For"), got.Get("X-Real-Ip"))
		}
	}
}

func TestOtherPeerCannotSetClientIP(t *testing.T) {
	got := serve(t, "10.0.0.8:40000", map[string]string{"CF-Connecting-IP": "203.0.113.7", "X-Forwarded-For": "1.2.3.4"})
	if got.Get("CF-Connecting-IP") != "" || got.Get("X-Real-Ip") != "" || got.Get("X-Forwarded-For") != "1.2.3.4" {
		t.Errorf("untrusted peer changed client IP headers: %v", got)
	}
}

func TestLoopbackPeerWithBadHeaderChangesNothing(t *testing.T) {
	got := serve(t, "127.0.0.1:40000", map[string]string{"CF-Connecting-IP": "not-an-ip", "X-Forwarded-For": "203.0.113.7"})
	if got.Get("X-Forwarded-For") != "203.0.113.7" || got.Get("X-Real-Ip") != "" {
		t.Errorf("bad CF-Connecting-IP was used: %v", got)
	}
}

func TestInvalidCIDRIsAnError(t *testing.T) {
	cfg := CreateConfig()
	cfg.TrustedIPs = []string{"127.0.0.1/33"}
	if _, err := New(context.Background(), http.NotFoundHandler(), cfg, "real-ip"); err == nil {
		t.Error("expected an error for an invalid CIDR")
	}
}

// Authelia (forwardAuth, trustForwardHeader) decides on X-Forwarded-Host/-Uri/
// -Method. Cloudflare passes the client's own on, so they must be dropped and
// refilled by Traefik from the real request.
func TestClientCannotChooseWhatAutheliaChecks(t *testing.T) {
	forged := map[string]string{
		"CF-Connecting-IP":   "203.0.113.7",
		"X-Forwarded-Host":   "searxng.example.com",
		"X-Forwarded-Uri":    "/public",
		"X-Forwarded-Method": "OPTIONS",
		"X-Forwarded-Prefix": "/x",
	}
	for _, peer := range []string{"127.0.0.1:40000", "10.0.0.8:40000"} {
		got := serve(t, peer, forged)
		if got.Get("X-Forwarded-Host") != "auth.example.com" {
			t.Errorf("peer %s: X-Forwarded-Host = %q, want the request's host", peer, got.Get("X-Forwarded-Host"))
		}
		for _, h := range []string{"X-Forwarded-Uri", "X-Forwarded-Method", "X-Forwarded-Prefix"} {
			if got.Get(h) != "" {
				t.Errorf("peer %s: %s kept: %q", peer, h, got.Get(h))
			}
		}
	}
}
