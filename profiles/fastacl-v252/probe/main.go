package main

import (
	"bufio"
	"context"
	"crypto/tls"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"net"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/daeuniverse/outbound/dialer"
	_ "github.com/daeuniverse/outbound/dialer/http"
	_ "github.com/daeuniverse/outbound/dialer/hysteria2"
	_ "github.com/daeuniverse/outbound/dialer/shadowsocks"
	_ "github.com/daeuniverse/outbound/dialer/socks"
	_ "github.com/daeuniverse/outbound/dialer/trojan"
	_ "github.com/daeuniverse/outbound/dialer/tuic"
	_ "github.com/daeuniverse/outbound/dialer/v2ray"
	"github.com/daeuniverse/outbound/netproxy"
	_ "github.com/daeuniverse/outbound/protocol/vless"
	_ "github.com/daeuniverse/outbound/protocol/vmess"
)

type encryptedBase struct{}

func (encryptedBase) DialContext(ctx context.Context, network, address string) (netproxy.Conn, error) {
	resolver := &net.Resolver{PreferGo: true, StrictErrors: true, Dial: func(ctx context.Context, network, address string) (net.Conn, error) {
		d := net.Dialer{Timeout: 5 * time.Second}
		return d.DialContext(ctx, network, "127.0.0.1:12553")
	}}
	d := net.Dialer{Timeout: 6 * time.Second, Resolver: resolver}
	return d.DialContext(ctx, network, address)
}

type result struct {
	OK      bool   `json:"ok"`
	IP      string `json:"ip,omitempty"`
	Country string `json:"country,omitempty"`
	Colo    string `json:"colo,omitempty"`
	Error   string `json:"error,omitempty"`
}

func output(v result, code int) {
	_ = json.NewEncoder(os.Stdout).Encode(v)
	os.Exit(code)
}

func probe(link string, timeout time.Duration) (result, error) {
	if len(link) == 0 || len(link) > 16384 || strings.ContainsAny(link, "\r\n\x00") {
		return result{}, errors.New("invalid node link")
	}
	d, _, err := dialer.NewNetproxyDialerFromLink(encryptedBase{}, &dialer.ExtraOption{AllowInsecure: false}, link)
	if err != nil {
		return result{}, fmt.Errorf("unsupported or invalid node: %w", err)
	}
	tr := &http.Transport{
		Proxy:             nil,
		TLSClientConfig:   &tls.Config{ServerName: "one.one.one.one", MinVersion: tls.VersionTLS12},
		ForceAttemptHTTP2: true,
		TLSHandshakeTimeout: 6 * time.Second,
		IdleConnTimeout:   10 * time.Second,
	}
	tr.DialContext = func(ctx context.Context, network, address string) (net.Conn, error) {
		c, e := d.DialContext(ctx, "tcp", "1.1.1.1:443")
		if e != nil {
			return nil, e
		}
		return &netproxy.FakeNetConn{Conn: c, LAddr: &net.TCPAddr{}, RAddr: &net.TCPAddr{IP: net.ParseIP("1.1.1.1"), Port: 443}}, nil
	}
	client := &http.Client{Transport: tr, Timeout: timeout, CheckRedirect: func(req *http.Request, via []*http.Request) error {
		return errors.New("redirect refused")
	}}
	req, err := http.NewRequest(http.MethodGet, "https://one.one.one.one/cdn-cgi/trace", nil)
	if err != nil {
		return result{}, err
	}
	req.Header.Set("User-Agent", "JuLiangTK-FastACL252-Probe/1")
	resp, err := client.Do(req)
	if err != nil {
		return result{}, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return result{}, fmt.Errorf("probe HTTP %d", resp.StatusCode)
	}
	out := result{OK: true}
	s := bufio.NewScanner(resp.Body)
	for s.Scan() {
		line := s.Text()
		if strings.HasPrefix(line, "ip=") {
			out.IP = strings.TrimSpace(strings.TrimPrefix(line, "ip="))
		} else if strings.HasPrefix(line, "loc=") {
			out.Country = strings.TrimSpace(strings.TrimPrefix(line, "loc="))
		} else if strings.HasPrefix(line, "colo=") {
			out.Colo = strings.TrimSpace(strings.TrimPrefix(line, "colo="))
		}
	}
	if err := s.Err(); err != nil {
		return result{}, err
	}
	ip := net.ParseIP(out.IP)
	if ip == nil || ip.To4() == nil {
		return result{}, errors.New("probe returned no IPv4")
	}
	return out, nil
}

func main() {
	link := flag.String("link", "", "dae/outbound node link to probe")
	seconds := flag.Int("timeout", 12, "probe timeout in seconds")
	flag.Parse()
	if *seconds < 3 || *seconds > 30 {
		output(result{OK: false, Error: "timeout must be 3-30 seconds"}, 2)
	}
	v, err := probe(*link, time.Duration(*seconds)*time.Second)
	if err != nil {
		output(result{OK: false, Error: err.Error()}, 1)
	}
	output(v, 0)
}
