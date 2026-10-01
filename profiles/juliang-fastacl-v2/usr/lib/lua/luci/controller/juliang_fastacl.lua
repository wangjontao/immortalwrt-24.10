module("luci.controller.juliang_fastacl", package.seeall)

function index()
    local page = entry({"admin", "services", "juliang_fastacl"}, call("handle"), nil)
    page.leaf = true
    page.dependent = false
end

local function write_json(t)
    local http = require "luci.http"
    local jsonc = require "luci.jsonc"
    http.prepare_content("application/json")
    http.write(jsonc.stringify(t))
end

local function ap_number(v)
    local n = tonumber((v or ""):match("^AP(%d+)$"))
    if n and n >= 1 and n <= 20 then return n end
    return nil
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

local function read_ip(n)
    local f = io.open("/tmp/juliang-fastacl/ap" .. n .. ".ip", "r")
    if not f then return "" end
    local ip = (f:read("*l") or ""):gsub("%s+", "")
    f:close()
    return ip
end

local function runtime_status()
    local f = io.open("/tmp/juliang-fastacl/router.pid", "r")
    if not f then return "stopped" end
    local pid = tonumber(f:read("*l") or "")
    f:close()
    if not pid then return "stopped" end
    local sys = require "luci.sys"
    return sys.call("kill -0 " .. pid .. " >/dev/null 2>&1") == 0 and "running" or "stopped"
end

local function exec_json(cmd)
    local sys = require "luci.sys"
    local jsonc = require "luci.jsonc"
    local raw = sys.exec(cmd .. " 2>/tmp/juliang-fastacl/luci-error.log")
    local ok, data = pcall(jsonc.parse, raw or "")
    if ok and type(data) == "table" then
        return data
    end
    return {
        ok = false,
        error = "ENGINE_ERROR",
        detail = raw or ""
    }
end

local function is_special_protocol(p)
    return p == "_shunt" or p == "_balancing" or p == "_urltest" or p == "_iface"
end

local function preproxy_options(uci, current)
    local out = {}
    uci:foreach("passwall2", "nodes", function(s)
        local id = s[".name"] or ""
        local proto = s.protocol or ""
        local chained = s.chain_proxy or ""
        if id ~= "" and id ~= current and not is_special_protocol(proto) and chained == "" then
            out[#out + 1] = {
                id = id,
                remarks = s.remarks or id,
                type = s.type or "",
                protocol = proto
            }
        end
    end)
    table.sort(out, function(a, b)
        return (a.remarks or "") < (b.remarks or "")
    end)
    return out
end

function handle()
    local http = require "luci.http"
    local util = require "luci.util"
    local uci = require("luci.model.uci").cursor()

    local action = http.formvalue("action") or "status"

    if action == "status" then
        local map = {}
        local ap_to_node = {}
        local ips = {}
        local labels = wireless_labels(uci)

        for i = 1, 20 do
            local ap = "AP" .. i
            local node = uci:get("juliang_fastacl", "ap" .. i, "node") or ""
            ap_to_node[ap] = node
            ips[ap] = read_ip(i)
            if node ~= "" then
                map[node] = map[node] or {}
                map[node][#map[node] + 1] = ap
            end
        end

        local preproxy = {}
        uci:foreach("passwall2", "nodes", function(s)
            local id = s[".name"] or ""
            if id ~= "" then
                local pp = s.preproxy_node or ""
                preproxy[id] = {
                    enabled = (s.chain_proxy == "1" and pp ~= ""),
                    id = pp,
                    remarks = pp ~= "" and (uci:get("passwall2", pp, "remarks") or pp) or ""
                }
            end
        end)

        write_json({
            ok = true,
            engine = runtime_status(),
            map = map,
            ap_to_node = ap_to_node,
            wireless_labels = labels,
            ips = ips,
            preproxy = preproxy
        })
        return
    end

    local node = http.formvalue("node") or ""
    local node_cfg = node ~= "" and uci:get_all("passwall2", node) or nil

    if action == "assign" then
        local ap = http.formvalue("ap") or ""
        local n = ap_number(ap)
        if not n then
            write_json({ ok = false, error = "BAD_AP" })
            return
        end
        if not node_cfg or node_cfg[".type"] ~= "nodes" then
            write_json({ ok = false, error = "BAD_NODE" })
            return
        end

        local exclusive = http.formvalue("exclusive") ~= "0"
        local verb = exclusive and "move" or "switch"
        local result = exec_json(
            "/usr/bin/juliang-fastacl " .. verb .. " " ..
            ap .. " " .. util.shellquote(node)
        )
        write_json(result)
        return
    end

    if action == "preproxy_options" then
        if not node_cfg or node_cfg[".type"] ~= "nodes" then
            write_json({ ok = false, error = "BAD_NODE" })
            return
        end
        write_json({
            ok = true,
            current = node_cfg.preproxy_node or "",
            enabled = node_cfg.chain_proxy == "1",
            options = preproxy_options(uci, node)
        })
        return
    end

    if action == "set_preproxy" then
        if not node_cfg or node_cfg[".type"] ~= "nodes" then
            write_json({ ok = false, error = "BAD_NODE" })
            return
        end

        local pre = http.formvalue("preproxy") or ""
        if pre == node then
            write_json({ ok = false, error = "PREPROXY_SELF" })
            return
        end

        if pre ~= "" then
            local p = uci:get_all("passwall2", pre)
            if not p or p[".type"] ~= "nodes" or is_special_protocol(p.protocol or "") then
                write_json({ ok = false, error = "BAD_PREPROXY" })
                return
            end
            if (p.chain_proxy or "") ~= "" then
                write_json({ ok = false, error = "PREPROXY_ALREADY_CHAINED" })
                return
            end
        end

        local old_chain = node_cfg.chain_proxy or ""
        local old_pre = node_cfg.preproxy_node or ""

        if pre == "" then
            uci:delete("passwall2", node, "chain_proxy")
            uci:delete("passwall2", node, "preproxy_node")
        else
            uci:set("passwall2", node, "chain_proxy", "1")
            uci:set("passwall2", node, "preproxy_node", pre)
        end
        uci:commit("passwall2")

        local affected = {}
        local failed = nil
        for i = 1, 20 do
            if (uci:get("juliang_fastacl", "ap" .. i, "node") or "") == node then
                local ap = "AP" .. i
                local r = exec_json("/usr/bin/juliang-fastacl switch " .. ap .. " " .. util.shellquote(node))
                if not r.ok then
                    failed = r
                    break
                end
                affected[#affected + 1] = ap
            end
        end

        if failed then
            if old_chain == "" then
                uci:delete("passwall2", node, "chain_proxy")
            else
                uci:set("passwall2", node, "chain_proxy", old_chain)
            end
            if old_pre == "" then
                uci:delete("passwall2", node, "preproxy_node")
            else
                uci:set("passwall2", node, "preproxy_node", old_pre)
            end
            uci:commit("passwall2")
            for _, ap in ipairs(affected) do
                exec_json("/usr/bin/juliang-fastacl switch " .. ap .. " " .. util.shellquote(node))
            end
            write_json({
                ok = false,
                error = "PREPROXY_START_FAILED",
                detail = failed,
                rolled_back = true
            })
            return
        end

        local ip = ""
        if #affected > 0 then
            local sys = require "luci.sys"
            ip = (sys.exec("/usr/bin/juliang-fastacl probe " .. affected[1] .. " 2>/dev/null") or ""):gsub("%s+", "")
        end

        write_json({
            ok = true,
            action = "set_preproxy",
            node = node,
            preproxy = pre,
            preproxy_remarks = pre ~= "" and (uci:get("passwall2", pre, "remarks") or pre) or "",
            affected = affected,
            ip = ip
        })
        return
    end

    if action == "clear_node" then
        if not node_cfg or node_cfg[".type"] ~= "nodes" then
            write_json({ ok = false, error = "BAD_NODE" })
            return
        end

        local cleared = {}
        for i = 1, 20 do
            if (uci:get("juliang_fastacl", "ap" .. i, "node") or "") == node then
                local ap = "AP" .. i
                local r = exec_json("/usr/bin/juliang-fastacl clear " .. ap)
                if r.ok then cleared[#cleared + 1] = ap end
            end
        end

        write_json({ ok = true, action = "clear_node", node = node, cleared = cleared })
        return
    end

    if action == "probe" then
        local ap = http.formvalue("ap") or ""
        local n = ap_number(ap)
        if not n then
            write_json({ ok = false, error = "BAD_AP" })
            return
        end
        local sys = require "luci.sys"
        local ip = (sys.exec("/usr/bin/juliang-fastacl probe " .. ap .. " 2>/dev/null") or ""):gsub("%s+", "")
        write_json({ ok = ip ~= "" and ip ~= "-", ap = ap, ip = ip })
        return
    end

    write_json({ ok = false, error = "BAD_ACTION" })
end
