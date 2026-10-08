package main

import (
 "bytes"
 "context"
 "crypto/tls"
 "encoding/binary"
 "encoding/json"
 "errors"
 "flag"
 "fmt"
 "io"
 "log"
 "net"
 "net/http"
 "os"
 "strconv"
 "sync"
 "time"
 "github.com/daeuniverse/outbound/netproxy"
)

type Config struct { Listen string `json:"listen"`; DirectIP string `json:"direct_ip"`; DirectName string `json:"direct_name"`; PrivateIP string `json:"private_ip"`; PrivateName string `json:"private_name"`; Devices map[string]int `json:"devices"`; Exits map[string]string `json:"exits"` }
type entry struct { data []byte; created time.Time; ttl uint32; offsets []int }
type relay struct { config Config; exits map[int]netproxy.Dialer; mu sync.Mutex; clients map[int]*http.Client; cache map[string]entry; slots chan struct{} }
func skipName(b []byte, p int) (int,error) {
 for n:=0;n<128;n++ { if p>=len(b) {return 0,io.ErrUnexpectedEOF}; l:=int(b[p]); p++; if l==0 {return p,nil}; if l&192==192 {if p>=len(b){return 0,io.ErrUnexpectedEOF};return p+1,nil}; if l>63 || p+l>len(b) {return 0,errors.New("invalid DNS name")};p+=l };return 0,errors.New("long DNS name")
}
func questionEnd(b []byte) (int,error) { if len(b)<12 || binary.BigEndian.Uint16(b[4:6])!=1 { return 0,errors.New("one DNS question required") };p,e:=skipName(b,12); if e!=nil || p+4>len(b){return 0,errors.New("invalid DNS question")}; return p+4,nil }
func ttlInfo(b []byte) (uint32,[]int) {
 p,e:=questionEnd(b);if e!=nil || b[3]&15!=0 || b[2]&2!=0 {return 0,nil}; count:=int(binary.BigEndian.Uint16(b[6:8]));if count==0{return 0,nil}; count+=int(binary.BigEndian.Uint16(b[8:10]))+int(binary.BigEndian.Uint16(b[10:12]));min:=uint32(300); offsets:=[]int{}
 for i:=0;i<count;i++ {p,e=skipName(b,p);if e!=nil || p+10>len(b){return 0,nil};typ:=binary.BigEndian.Uint16(b[p:p+2]); ttl:=binary.BigEndian.Uint32(b[p+4:p+8]);size:=int(binary.BigEndian.Uint16(b[p+8:p+10]));if typ!=41 {offsets=append(offsets,p+4);if ttl<min {min=ttl}};p+=10+size;if p>len(b){return 0,nil} };return min,offsets
}
func fail(q []byte) []byte {p,e:=questionEnd(q);if e!=nil {return nil};b:=append([]byte(nil),q[:p]...);b[2]=(b[2]&1)|128;b[3]=(b[3]&16)|128|2;for i:=6;i<12;i++{b[i]=0};return b}
func socks(ctx context.Context, port int, ip string) (net.Conn,error) {
 d:=net.Dialer{Timeout:5*time.Second};c,e:=d.DialContext(ctx,"tcp",net.JoinHostPort("127.0.0.1",strconv.Itoa(port)));if e!=nil{return nil,e};ok:=false;defer func(){if !ok {c.Close()}}();c.SetDeadline(time.Now().Add(8*time.Second))
 if _,e=c.Write([]byte{5,1,0});e!=nil{return nil,e};reply:=make([]byte,2);if _,e=io.ReadFull(c,reply);e!=nil || reply[0]!=5 || reply[1]!=0 {return nil,errors.New("SOCKS authentication failed")}
 v:=net.ParseIP(ip).To4();if v==nil{return nil,errors.New("IPv4 DNS endpoint required")};req:=append([]byte{5,1,0,1},v...);req=append(req,1,187);if _,e=c.Write(req);e!=nil{return nil,e};h:=make([]byte,4);if _,e=io.ReadFull(c,h);e!=nil || h[0]!=5 || h[1]!=0{return nil,errors.New("SOCKS connect failed")};n:=0;switch h[3] {case 1:n=4;case 4:n=16;case 3:x:=make([]byte,1);if _,e=io.ReadFull(c,x);e!=nil{return nil,e};n=int(x[0]);default:return nil,errors.New("invalid SOCKS reply")};if _,e=io.CopyN(io.Discard,c,int64(n+2));e!=nil{return nil,e};c.SetDeadline(time.Time{});ok=true;return c,nil
}
func (r *relay) client(port int) *http.Client {
 r.mu.Lock();defer r.mu.Unlock();if c:=r.clients[port];c!=nil{return c};ip,name:=r.config.DirectIP,r.config.DirectName;if port!=0 {ip,name=r.config.PrivateIP,r.config.PrivateName}
 t:=&http.Transport{Proxy:nil,TLSClientConfig:&tls.Config{ServerName:name,MinVersion:tls.VersionTLS12},ForceAttemptHTTP2:true,MaxIdleConns:8,MaxIdleConnsPerHost:2,IdleConnTimeout:60*time.Second,TLSHandshakeTimeout:5*time.Second}
 t.DialContext=func(ctx context.Context,network,address string)(net.Conn,error){if port!=0{return r.privateDial(ctx,port,ip)};d:=net.Dialer{Timeout:5*time.Second};return d.DialContext(ctx,"tcp",net.JoinHostPort(ip,"443"))};c:=&http.Client{Transport:t,Timeout:8*time.Second,CheckRedirect:func(req *http.Request,via []*http.Request)error{return errors.New("DoH redirect refused")}};r.clients[port]=c;return c
}
func (r *relay) resolve(q []byte,ip string) []byte {
 if _,e:=questionEnd(q);e!=nil || q[2]&128!=0{return nil};select{case r.slots<-struct{}{}:defer func(){<-r.slots}();default:return fail(q)}
 port:=r.config.Devices[ip];key:=strconv.Itoa(port)+":"+string(q[2:]);r.mu.Lock();v,ok:=r.cache[key];if ok && uint32(time.Since(v.created)/time.Second)<v.ttl {b:=append([]byte(nil),v.data...);age:=uint32(time.Since(v.created)/time.Second);for _,p:=range v.offsets {ttl:=binary.BigEndian.Uint32(b[p:p+4]);if age>ttl{ttl=0}else{ttl-=age};binary.BigEndian.PutUint32(b[p:p+4],ttl)};copy(b[:2],q[:2]);r.mu.Unlock();return b};delete(r.cache,key);r.mu.Unlock()
 name:=r.config.DirectName;if port!=0{name=r.config.PrivateName};req,e:=http.NewRequest("POST","https://"+name+"/dns-query",bytes.NewReader(q));if e!=nil{return fail(q)};req.Header.Set("Content-Type","application/dns-message");req.Header.Set("Accept","application/dns-message");resp,e:=r.client(port).Do(req);if e!=nil{return fail(q)};defer resp.Body.Close();if resp.StatusCode!=200{return fail(q)};b,e:=io.ReadAll(io.LimitReader(resp.Body,65536));if e!=nil || len(b)<12 || len(b)>65535 || b[2]&128==0 || !bytes.Equal(b[:2],q[:2]) {return fail(q)}
 qe,_:=questionEnd(q);be,e:=questionEnd(b);if e!=nil || !bytes.Equal(q[12:qe],b[12:be]){return fail(q)};ttl,offsets:=ttlInfo(b);if ttl>0 && len(b)<=8192 {r.mu.Lock();if len(r.cache)>=256 {for k:=range r.cache {delete(r.cache,k);break}};r.cache[key]=entry{append([]byte(nil),b...),time.Now(),ttl,offsets};r.mu.Unlock()};return b
}
func (r *relay) tcp(c net.Conn) {defer c.Close();ip,_,_:=net.SplitHostPort(c.RemoteAddr().String());for {c.SetDeadline(time.Now().Add(12*time.Second));h:=make([]byte,2);if _,e:=io.ReadFull(c,h);e!=nil{return};q:=make([]byte,int(binary.BigEndian.Uint16(h)));if _,e:=io.ReadFull(c,q);e!=nil{return};b:=r.resolve(q,ip);if b==nil{return};binary.BigEndian.PutUint16(h,uint16(len(b)));if _,e:=c.Write(append(h,b...));e!=nil{return}}}
func main() {
 file:=flag.String("config","","configuration JSON");check:=flag.Bool("check",false,"validate native nodes without listening");flag.Parse();b,e:=os.ReadFile(*file);if e!=nil{log.Fatal(e)};var cfg Config;if e=json.Unmarshal(b,&cfg);e!=nil{log.Fatal(e)};if net.ParseIP(cfg.DirectIP).To4()==nil || net.ParseIP(cfg.PrivateIP).To4()==nil || cfg.DirectName=="" || cfg.PrivateName==""{log.Fatal("invalid DNS configuration")};for _,port:=range cfg.Devices {if port<12600 || port>=14000{log.Fatal("invalid proxy port")}}
 exits,e:=makeExits(cfg);if e!=nil{log.Fatal(e)};if *check{return};r:=&relay{config:cfg,exits:exits,clients:map[int]*http.Client{},cache:map[string]entry{},slots:make(chan struct{},64)};ua,e:=net.ResolveUDPAddr("udp4",cfg.Listen);if e!=nil{log.Fatal(e)};u,e:=net.ListenUDP("udp4",ua);if e!=nil{log.Fatal(e)};t,e:=net.Listen("tcp4",cfg.Listen);if e!=nil{log.Fatal(e)};connections:=make(chan struct{},128)
 go func(){for {c,e:=t.Accept();if e!=nil{return};select {case connections<-struct{}{}:go func(){defer func(){<-connections}();r.tcp(c)}();default:c.Close()}}}();fmt.Println("FastACL 2.5.2 encrypted DNS ready")
 for {b:=make([]byte,65535);n,a,e:=u.ReadFromUDP(b);if e!=nil{log.Fatal(e)};q:=append([]byte(nil),b[:n]...);go func(){reply:=r.resolve(q,a.IP.String());if reply!=nil{u.WriteToUDP(reply,a)}}()}
}
