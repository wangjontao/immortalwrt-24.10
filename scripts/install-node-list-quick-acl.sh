#!/bin/sh
set -eu

VERSION="1.4.0"
MARKER="JULIANG_QUICK_ACL_V14"
CTRL="/usr/lib/lua/luci/controller/juliang_quick_acl.lua"

echo "=================================================="
echo " JuLiang Quick ACL Node Bind v$VERSION"
echo " PassWall / PassWall2 节点列表快捷绑定 AP1-AP20"
echo "=================================================="

command -v lua >/dev/null 2>&1 || {
  echo "[ERROR] lua not found"
  exit 1
}

mkdir -p /usr/lib/lua/luci/controller

cat > "$CTRL" <<'LUA_CTRL'
module("luci.controller.juliang_quick_acl", package.seeall)

function index()
    local page = entry({"admin", "services", "juliang_quick_acl"}, call("handle"), nil)
    page.leaf = true
    page.dependent = false
end

local function write_json(t)
    local http = require "luci.http"
    local jsonc = require "luci.jsonc"
    http.prepare_content("application/json")
    http.write(jsonc.stringify(t))
end

local function valid_app(app)
    return app == "passwall" or app == "passwall2"
end

local function ap_number(v)
    local n = tonumber((v or ""):match("^AP(%d+)$"))
    if n and n >= 1 and n <= 20 then return n end
    return nil
end

local function find_global(uci, app)
    local found
    uci:foreach(app, "global", function(s)
        if not found then found = s[".name"] end
    end)
    return found
end

local function find_acl(uci, app, acl)
    local found
    local n = ap_number(acl)
    if not n then return nil end
    local subnet = string.format("172.16.%d.0/24", n)

    uci:foreach(app, "acl_rule", function(s)
        if found then return end
        if s.remarks == acl or s.sources == subnet then
            found = s[".name"]
        end
    end)
    return found
end

local function acl_node(app, s)
    if app == "passwall2" then
        return s.node
    end
    return s.tcp_node
end

local function clear_acl_node(uci, app, section)
    if app == "passwall2" then
        uci:delete(app, section, "node")
    else
        uci:delete(app, section, "tcp_node")
        uci:delete(app, section, "udp_node")
    end
end

local function restart_async(app)
    local sys = require "luci.sys"
    sys.call(string.format(
        "(sleep 1; /etc/init.d/%s restart >/tmp/%s-quick-acl.log 2>&1) >/dev/null 2>&1 &",
        app, app
    ))
end

local function wireless_labels(uci)
    local labels = {}
    for i = 1, 20 do
        labels["AP" .. i] = "无线AP" .. i
    end

    uci:foreach("wireless", "wifi-iface", function(s)
        local network = s.network or ""
        local ssid = s.ssid or ""
        if ssid ~= "" then
            for i = 1, 20 do
                local tk = "tk" .. i
                if (" " .. network .. " "):find(" " .. tk .. " ", 1, true) then
                    labels["AP" .. i] = "无线" .. ssid
                end
            end
        end
    end)

    return labels
end

function handle()
    local http = require "luci.http"
    local uci = require("luci.model.uci").cursor()

    local app = http.formvalue("app") or ""
    local action = http.formvalue("action") or "status"

    if not valid_app(app) then
        write_json({ ok = false, error = "BAD_APP" })
        return
    end

    if action == "status" then
        local map = {}
        local acl_to_node = {}

        uci:foreach(app, "acl_rule", function(s)
            local label = s.remarks or ""
            if ap_number(label) then
                local node = acl_node(app, s)
                if node and node ~= "" then
                    map[node] = map[node] or {}
                    table.insert(map[node], label)
                    acl_to_node[label] = node
                end
            end
        end)

        write_json({
            ok = true,
            map = map,
            acl_to_node = acl_to_node,
            wireless_labels = wireless_labels(uci)
        })
        return
    end

    local node = http.formvalue("node") or ""
    local node_cfg = node ~= "" and uci:get_all(app, node) or nil
    if not node_cfg or node_cfg[".type"] ~= "nodes" then
        write_json({ ok = false, error = "BAD_NODE" })
        return
    end

    if action == "assign" then
        local acl = http.formvalue("acl") or ""
        local target = find_acl(uci, app, acl)
        if not target then
            write_json({ ok = false, error = "ACL_NOT_FOUND", acl = acl })
            return
        end

        local exclusive = http.formvalue("exclusive") ~= "0"

        if exclusive then
            uci:foreach(app, "acl_rule", function(s)
                if ap_number(s.remarks or "") and s[".name"] ~= target and acl_node(app, s) == node then
                    clear_acl_node(uci, app, s[".name"])
                end
            end)
        end

        local global = find_global(uci, app)
        if global then
            uci:set(app, global, "acl_enable", "1")
        end

        uci:set(app, target, "enabled", "1")

        if app == "passwall2" then
            uci:set(app, target, "node", node)
        else
            uci:set(app, target, "use_global_config", "0")
            uci:set(app, target, "tcp_node", node)
            uci:set(app, target, "udp_node", "tcp")
        end

        uci:commit(app)
        local pf = io.open("/tmp/juliang-quick-acl-" .. app .. ".pending", "w")
        if pf then pf:write(os.time(), "\n"); pf:close() end

        write_json({
            ok = true,
            action = "assign",
            node = node,
            acl = acl,
            exclusive = exclusive,
            pending = true
        })
        return
    end

    if action == "clear_node" then
        local cleared = {}
        uci:foreach(app, "acl_rule", function(s)
            local label = s.remarks or ""
            if ap_number(label) and acl_node(app, s) == node then
                clear_acl_node(uci, app, s[".name"])
                table.insert(cleared, label)
            end
        end)

        uci:commit(app)
        local pf = io.open("/tmp/juliang-quick-acl-" .. app .. ".pending", "w")
        if pf then pf:write(os.time(), "\n"); pf:close() end

        write_json({ ok = true, action = "clear_node", node = node, cleared = cleared, pending = true })
        return
    end

    if action == "apply" then
        os.remove("/tmp/juliang-quick-acl-" .. app .. ".pending")
        restart_async(app)
        write_json({ ok = true, action = "apply", restarting = true })
        return
    end

    write_json({ ok = false, error = "BAD_ACTION" })
end
LUA_CTRL

lua -e "assert(loadfile('$CTRL'))"

patch_template() {
    APP="$1"
    FILE="/usr/lib/lua/luci/view/$APP/node_list/node_list.htm"

    [ -f "$FILE" ] || {
        echo "[SKIP] $FILE not found"
        return 0
    }

    if grep -q "$MARKER" "$FILE"; then
        echo "[OK] $APP already patched"
        return 0
    fi

    # v1.0 could leave a partial patch (modal/top variable but no ACL button).
    # If a backup exists and the marker is absent, restore the original first.
    if [ -f "$FILE.quick-acl.bak" ]; then
        echo "[INFO] $APP: restoring original template from previous partial patch"
        cp -af "$FILE.quick-acl.bak" "$FILE"
    else
        cp -a "$FILE" "$FILE.quick-acl.bak"
    fi

    echo "[INFO] $APP: patching node list template"
    FILE="$FILE" APP="$APP" lua <<'LUA_PATCH'
local file = assert(os.getenv("FILE"))
local app = assert(os.getenv("APP"))

local f = assert(io.open(file, "r"))
local text = f:read("*a")
f:close()

local marker = "JULIANG_QUICK_ACL_V14"
if text:find(marker, 1, true) then
    os.exit(0)
end

local function replace_once(src, needle, repl, label)
    local s, e = src:find(needle, 1, true)
    assert(s, (label or "anchor") .. " missing")
    return src:sub(1, s - 1) .. repl .. src:sub(e + 1)
end

local top_old = 'local appname = api.appname\n'
local top_new = 'local appname = api.appname\nlocal quick_acl_url = require("luci.dispatcher").build_url("admin", "services", "juliang_quick_acl")\n'
text = replace_once(text, top_old, top_new, "top anchor")

local js_anchor = '\n\tfunction to_edit_node(cbi_id) {'
local js = [[

    // JULIANG_QUICK_ACL_V14
    var quickAclNode = "";
    var quickAclMap = {};
    var quickAclWirelessLabels = {};

    function quick_acl_label(acl) {
        return quickAclWirelessLabels[acl] || ("无线" + acl);
    }

    function quick_acl_summary(list) {
        if (!list || !list.length) return "未分配";
        return list.map(quick_acl_label).join(", ");
    }

    function quick_acl_refresh_select_labels() {
        var sel = document.getElementById("quick_acl_select");
        if (!sel) return;
        for (var i = 0; i < sel.options.length; i++) {
            var v = sel.options[i].value;
            if (/^AP([1-9]|1[0-9]|20)$/.test(v)) {
                var n = v.replace("AP", "");
                sel.options[i].text = quick_acl_label(v) + " · 172.16." + n + ".0/24";
            }
        }
    }

    function quick_acl_update_buttons() {
        var buttons = document.getElementsByClassName("quick-acl-btn");
        for (var i = 0; i < buttons.length; i++) {
            var id = buttons[i].getAttribute("data-node-id");
            var list = quickAclMap[id] || [];
            buttons[i].value = list.length ? list.map(quick_acl_label).join(",") : "分配无线";
            buttons[i].title = list.length ? ("已分配：" + list.map(quick_acl_label).join(", ")) : "未分配无线";
        }
    }

    function quick_acl_load_status(done) {
        XHR.get('<%=quick_acl_url%>', {
            app: '<%=appname%>',
            action: 'status'
        }, function(x, result) {
            if (x && x.status == 200 && result && result.ok) {
                quickAclMap = result.map || {};
                quickAclWirelessLabels = result.wireless_labels || {};
                quick_acl_refresh_select_labels();
                quick_acl_update_buttons();
            }
            if (done) done(result || {});
        });
    }

    function quick_acl_open(cbi_id) {
        quickAclNode = cbi_id;
        var name = (document.getElementById("cbid.<%=appname%>." + cbi_id + ".remarks") || {}).value || cbi_id;
        document.getElementById("quick_acl_node_name").innerText = name;
        document.getElementById("quick_acl_div").style.display = "block";

        quick_acl_load_status(function() {
            var list = quickAclMap[cbi_id] || [];
            document.getElementById("quick_acl_current").innerText = quick_acl_summary(list);
            var sel = document.getElementById("quick_acl_select");
            if (list.length && /^AP([1-9]|1[0-9]|20)$/.test(list[0])) sel.value = list[0];
        });
    }

    function quick_acl_close() {
        document.getElementById("quick_acl_div").style.display = "none";
        quickAclNode = "";
    }

    function quick_acl_apply(btn) {
        if (btn) {
            btn.disabled = true;
            btn.value = "应用中…";
        }

        XHR.get('<%=quick_acl_url%>', {
            app: '<%=appname%>',
            action: 'apply'
        }, function(x, result) {
            if (btn) {
                btn.disabled = false;
                btn.value = "保存并应用无线";
            }

            if (x && x.status == 200 && result && result.ok) {
                alert("无线分配已保存，正在统一重载代理规则。\n这次只重启一次。");
            } else {
                alert("应用失败：" + ((result && result.error) || "ERROR"));
            }
        });
    }

    function quick_acl_assign() {
        if (!quickAclNode) return;
        var acl = document.getElementById("quick_acl_select").value;
        if (!acl) {
            alert("请选择 AP1-AP20");
            return;
        }

        var exclusive = document.getElementById("quick_acl_exclusive").checked ? "1" : "0";
        var status = document.getElementById("quick_acl_status");
        status.innerText = "保存中…";

        XHR.get('<%=quick_acl_url%>', {
            app: '<%=appname%>',
            action: 'assign',
            node: quickAclNode,
            acl: acl,
            exclusive: exclusive
        }, function(x, result) {
            if (x && x.status == 200 && result && result.ok) {
                status.innerText = "已保存到 " + quick_acl_label(acl) + "，尚未应用";
                quick_acl_load_status(function() {
                    document.getElementById("quick_acl_current").innerText =
                        quick_acl_summary(quickAclMap[quickAclNode] || []);
                });
            } else {
                status.innerText = "保存失败：" + ((result && result.error) || "ERROR");
            }
        });
    }

    function quick_acl_clear_node() {
        if (!quickAclNode) return;
        if (!confirm("解除这个节点当前绑定的所有 AP ACL？")) return;

        var status = document.getElementById("quick_acl_status");
        status.innerText = "解除中…";

        XHR.get('<%=quick_acl_url%>', {
            app: '<%=appname%>',
            action: 'clear_node',
            node: quickAclNode
        }, function(x, result) {
            if (x && x.status == 200 && result && result.ok) {
                status.innerText = "已解除绑定，尚未应用";
                quick_acl_load_status(function() {
                    document.getElementById("quick_acl_current").innerText = "未分配";
                });
            } else {
                status.innerText = "解除失败：" + ((result && result.error) || "ERROR");
            }
        });
    }
]]
text = replace_once(text, js_anchor, js .. js_anchor, "JS anchor")

local copy_anchor = '\n\t\t\t\t<input class="btn cbi-button cbi-button-add" type="button" value="<%:Copy%>" onclick="copy_node(\'{{id}}\')"/>'
local acl_button = '\n\t\t\t\t<input class="btn cbi-button cbi-button-edit quick-acl-btn" type="button" id="quick_acl_{{id}}" data-node-id="{{id}}" value="ACL" onclick="quick_acl_open(\'{{id}}\')" title="快捷分配 AP1-AP20"/>'
text = replace_once(text, copy_anchor, acl_button .. copy_anchor, "button anchor")

local ping_call = '\n\t\t\tpingAllNodes();'
text = replace_once(text, ping_call, ping_call .. '\n\t\t\tquick_acl_load_status();', "load status anchor")

local modal = [[

<div id="quick_acl_div" style="display:none; width:32rem; max-width:92vw; position:fixed; left:50%; top:50%; transform:translate(-50%,-50%); z-index:120; padding:20px; text-align:center; background:var(--main-bg-color,#fff); border-radius:10px; box-shadow:0 10px 36px rgba(0,0,0,.35);">
    <div style="font-size:16px;font-weight:700;margin-bottom:12px;">快捷分配无线</div>
    <div style="margin:7px 0;">节点：<strong id="quick_acl_node_name" style="color:#159957"></strong></div>
    <div style="margin:7px 0;">当前：<strong id="quick_acl_current" style="color:#e6a23c">读取中…</strong></div>
    <div style="margin:12px 0;">
        <select id="quick_acl_select" class="cbi-input-select" style="min-width:180px;">
            <option value="">请选择无线</option>
            <option value="AP1">AP1 · 172.16.1.0/24</option>
            <option value="AP2">AP2 · 172.16.2.0/24</option>
            <option value="AP3">AP3 · 172.16.3.0/24</option>
            <option value="AP4">AP4 · 172.16.4.0/24</option>
            <option value="AP5">AP5 · 172.16.5.0/24</option>
            <option value="AP6">AP6 · 172.16.6.0/24</option>
            <option value="AP7">AP7 · 172.16.7.0/24</option>
            <option value="AP8">AP8 · 172.16.8.0/24</option>
            <option value="AP9">AP9 · 172.16.9.0/24</option>
            <option value="AP10">AP10 · 172.16.10.0/24</option>
            <option value="AP11">AP11 · 172.16.11.0/24</option>
            <option value="AP12">AP12 · 172.16.12.0/24</option>
            <option value="AP13">AP13 · 172.16.13.0/24</option>
            <option value="AP14">AP14 · 172.16.14.0/24</option>
            <option value="AP15">AP15 · 172.16.15.0/24</option>
            <option value="AP16">AP16 · 172.16.16.0/24</option>
            <option value="AP17">AP17 · 172.16.17.0/24</option>
            <option value="AP18">AP18 · 172.16.18.0/24</option>
            <option value="AP19">AP19 · 172.16.19.0/24</option>
            <option value="AP20">AP20 · 172.16.20.0/24</option>
        </select>
    </div>
    <label style="display:block;margin:9px 0;">
        <input id="quick_acl_exclusive" type="checkbox" checked="checked"/>
        唯一绑定：分配后自动解除该节点原来的其它无线
    </label>
    <div id="quick_acl_status" style="min-height:22px;margin:8px 0;color:#159957;"></div>
    <div style="display:flex;justify-content:center;gap:8px;flex-wrap:wrap;">
        <input class="btn cbi-button cbi-button-apply" type="button" value="保存分配" onclick="quick_acl_assign()"/>
        <input class="btn cbi-button cbi-button-remove" type="button" value="解除绑定" onclick="quick_acl_clear_node()"/>
        <input class="btn cbi-button cbi-button-edit" type="button" value="关闭" onclick="quick_acl_close()"/>
    </div>
</div>
]]

-- Append the modal to the template instead of relying on the exact upstream
-- set_node_div wrapper markup, which may differ between LuCI/PassWall builds.
text = text .. modal

local out = assert(io.open(file .. ".new", "w"))
out:write(text)
out:close()
os.rename(file .. ".new", file)
LUA_PATCH

    grep -q "$MARKER" "$FILE"
    grep -q 'quick-acl-btn' "$FILE"
    grep -q 'quick_acl_load_status' "$FILE"
    grep -q 'quick_acl_apply' "$FILE"
    grep -q '保存并应用无线' "$FILE"
    echo "[OK] patched $APP node list"
}

patch_template passwall
patch_template passwall2

cat > /usr/bin/uninstall-juliang-quick-acl <<'UNINSTALL'
#!/bin/sh
for APP in passwall passwall2; do
    FILE="/usr/lib/lua/luci/view/$APP/node_list/node_list.htm"
    if [ -f "$FILE.quick-acl.bak" ]; then
        cp -af "$FILE.quick-acl.bak" "$FILE"
        rm -f "$FILE.quick-acl.bak"
        echo "[OK] restored $APP"
    fi
done
rm -f /usr/lib/lua/luci/controller/juliang_quick_acl.lua
rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache /tmp/luci-templatecache
/etc/init.d/uhttpd restart >/dev/null 2>&1 || true
echo "[OK] JuLiang Quick ACL removed"
UNINSTALL
chmod 0755 /usr/bin/uninstall-juliang-quick-acl

rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache /tmp/luci-templatecache
/etc/init.d/uhttpd restart >/dev/null 2>&1 || true

echo
echo "=================================================="
echo " 安装完成"
echo "=================================================="
echo "打开 PassWall / PassWall2 -> 节点列表"
echo "每个节点右侧新增“分配无线/无线SSID”按钮"
echo "可直接分配无线 AP1-AP20（界面读取实际 SSID 名称），无需进入访问控制页面"
echo "默认“唯一绑定”，同一节点只绑定一个 AP"
echo "节点分配只保存配置，不再每次重启；全部分配完后点击“保存并应用无线”统一生效"
echo
echo "如需卸载："
echo "  /usr/bin/uninstall-juliang-quick-acl"
echo
echo "浏览器请 Ctrl+F5 强制刷新"
