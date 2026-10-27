"""Shared Lua bridge and configuration fixtures for FastACL 2.6.7 tests."""
import base64
import json
import pathlib

from lupa.lua51 import LuaRuntime

ROOT = pathlib.Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(
    "package.path="
    + json.dumps(str(ROOT / "root/usr/lib/lua/?.lua").replace("\\", "/"))
    + "..';'..package.path"
)
lua.globals().pyencode = lambda value: json.dumps(from_lua(value))
lua.globals().pyb64encode = lambda value: base64.b64encode(value.encode()).decode()
lua.execute(
    "package.preload['luci.jsonc']=function() return {stringify=pyencode} end;"
    "package.preload['nixio']=function() return {bin={b64encode=pyb64encode}} end"
)
policy = lua.eval("require('fastacl252')")


def to_lua(value):
    if isinstance(value, dict):
        return lua.table_from({key: to_lua(item) for key, item in value.items()})
    if isinstance(value, list):
        return lua.table_from([to_lua(item) for item in value])
    return value


def from_lua(value):
    if hasattr(value, "keys"):
        keys = list(value.keys())
        if keys and all(isinstance(key, int) for key in keys):
            return [from_lua(value[index]) for index in range(1, len(keys) + 1)]
        return {key: from_lua(value[key]) for key in keys}
    return value


def config():
    return dict(
        network="lan",
        interface="br-lan",
        router_ip="192.168.7.1",
        netmask="255.255.255.0",
        port=12525,
        default_mode="direct",
        dns_policy="direct",
        dns_server="223.5.5.5",
        dns_name="dns.alidns.com",
        private_dns_server="9.9.9.9",
        private_dns_name="dns.quad9.net",
        nodes={
            "us": dict(protocol="socks", address="proxy.example.com", port="1080", username="a", password="secret"),
            "jp": dict(protocol="http", address="203.0.113.8", port="8080"),
            "front": dict(
                protocol="vless",
                outbound=dict(
                    type="vless",
                    server="203.0.113.9",
                    server_port=443,
                    uuid="00000000-0000-0000-0000-000000000001",
                ),
            ),
        },
        devices=[
            dict(mac="02:00:00:00:00:01", ip="192.168.7.101", mode="proxy", node="us"),
            dict(mac="02:00:00:00:00:02", ip="192.168.7.102", mode="proxy", node="jp"),
            dict(mac="02:00:00:00:00:03", ip="192.168.7.103", mode="direct"),
        ],
    )


def compile(c):
    core, relay = policy.compile(to_lua(c))
    return from_lua(core), from_lua(relay)
