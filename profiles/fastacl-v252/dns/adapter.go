package main

import (
 "context"
 "fmt"
 "net"
 "strconv"
 "strings"
 "time"
 "github.com/daeuniverse/outbound/dialer"
 "github.com/daeuniverse/outbound/netproxy"
 _ "github.com/daeuniverse/outbound/dialer/socks"
 _ "github.com/daeuniverse/outbound/dialer/http"
 _ "github.com/daeuniverse/outbound/dialer/v2ray"
 _ "github.com/daeuniverse/outbound/dialer/trojan"
 _ "github.com/daeuniverse/outbound/dialer/shadowsocks"
 _ "github.com/daeuniverse/outbound/dialer/hysteria2"
 _ "github.com/daeuniverse/outbound/dialer/tuic"
)

// Endpoint names resolve only through this relay's pinned direct DoH path.
// No OS DNS fallback, and no second transparent proxy core.
type encryptedBase struct{}
func (encryptedBase) DialContext(ctx context.Context, network, address string) (netproxy.Conn,error) {
 resolver:=&net.Resolver{PreferGo:true,StrictErrors:true,Dial:func(ctx context.Context,network,address string)(net.Conn,error){
  d:=net.Dialer{Timeout:5*time.Second};return d.DialContext(ctx,network,"127.0.0.1:12553")
 }}
 d:=net.Dialer{Timeout:5*time.Second,Resolver:resolver}
 return d.DialContext(ctx,network,address)
}
func makeExits(cfg Config)(map[int]netproxy.Dialer,error) {
 result:=map[int]netproxy.Dialer{}
 for key,link:=range cfg.Exits {
  id,e:=strconv.Atoi(key);if e!=nil || id<12600 || id>=14000 || strings.ContainsAny(link,"\r\n\x00") {return nil,fmt.Errorf("invalid exit configuration")}
  d,_,e:=dialer.NewNetproxyDialerFromLink(encryptedBase{},&dialer.ExtraOption{AllowInsecure:false},link)
  if e!=nil {return nil,fmt.Errorf("exit %d: unsupported or invalid node",id)}
  result[id]=d
 }
 for _,id:=range cfg.Devices {if result[id]==nil{return nil,fmt.Errorf("device references missing exit")}}
 return result,nil
}
func (r *relay) privateDial(ctx context.Context,id int,ip string)(net.Conn,error) {
 d:=r.exits[id];if d==nil{return nil,fmt.Errorf("private DNS exit unavailable")}
 c,e:=d.DialContext(ctx,"tcp",net.JoinHostPort(ip,"443"));if e!=nil{return nil,e}
 return &netproxy.FakeNetConn{Conn:c,LAddr:&net.TCPAddr{},RAddr:&net.TCPAddr{IP:net.ParseIP(ip),Port:443}},nil
}
