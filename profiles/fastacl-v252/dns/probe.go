package main
import("context";"crypto/tls";"encoding/json";"fmt";"io";"net";"net/http";"os";"strings";"time";"github.com/daeuniverse/outbound/dialer";"github.com/daeuniverse/outbound/netproxy")
type probeSpec struct{ Link string `json:"link"` }
func runProbe(path string){
 start:=time.Now();result:=map[string]any{"ok":false}
 defer func(){json.NewEncoder(os.Stdout).Encode(result)}()
 b,e:=os.ReadFile(path);if e!=nil{result["error"]="无法读取检测配置";return};var spec probeSpec;if json.Unmarshal(b,&spec)!=nil{result["error"]="检测配置无效";return}
 var d netproxy.Dialer=encryptedBase{}
 if spec.Link!="" {d,_,e=dialer.NewNetproxyDialerFromLink(d,&dialer.ExtraOption{AllowInsecure:false},spec.Link);if e!=nil{result["error"]="节点协议无法检测";return}}
 t:=&http.Transport{TLSClientConfig:&tls.Config{ServerName:"1.1.1.1",MinVersion:tls.VersionTLS12},Proxy:nil,DisableKeepAlives:true}
 defer t.CloseIdleConnections()
 t.DialContext=func(ctx context.Context,network,address string)(net.Conn,error){c,e:=d.DialContext(ctx,"tcp","1.1.1.1:443");if e!=nil{return nil,e};return &netproxy.FakeNetConn{Conn:c,LAddr:&net.TCPAddr{},RAddr:&net.TCPAddr{IP:net.ParseIP("1.1.1.1"),Port:443}},nil}
 client:=&http.Client{Transport:t,Timeout:10*time.Second,CheckRedirect:func(*http.Request,[]*http.Request)error{return fmt.Errorf("redirect refused")}}
 r,e:=client.Get("https://1.1.1.1/cdn-cgi/trace");if e!=nil{result["error"]="连接失败或超时，未回退直连";return};defer r.Body.Close();if r.StatusCode!=200{result["error"]="出口检测服务返回异常";return}
 b,e=io.ReadAll(io.LimitReader(r.Body,16384));if e!=nil{result["error"]="读取出口响应失败";return}
 for _,line:=range strings.Split(string(b),"\n"){a:=strings.SplitN(line,"=",2);if len(a)!=2{continue};if a[0]=="ip"&&net.ParseIP(a[1])!=nil{result["ip"]=a[1]};if a[0]=="loc"&&len(a[1])==2{result["country"]=a[1]}}
 if result["ip"]==nil{result["error"]="未获得有效出口 IP";return};result["ok"]=true;result["proxy"]=spec.Link!="";result["elapsed_ms"]=time.Since(start).Milliseconds()
}
