#!/usr/bin/env python3
import copy
import unittest

import test_support


class VlanPolicyTests(unittest.TestCase):
    def config(self):
        c = copy.deepcopy(test_support.config())
        c["interfaces"] = ["br-lan", "eth1.10"]
        c["wifis"] = [dict(
            id="jfa25v10",
            kind="vlan",
            network="jfa25v10",
            interface="eth1.10",
            router_ip="192.168.10.1",
            netmask="255.255.255.0",
            subnet="192.168.10.0/24",
            mode="proxy",
            node="us",
        )]
        c["devices"].append(dict(
            mac="02:00:00:00:00:10",
            ip="192.168.10.101",
            network="jfa25v10",
            mode="proxy",
            node="us",
            split_mode="custom",
            split_rules="direct 1.1.1.0/24",
        ))
        return c

    def test_device_can_bind_inside_vlan(self):
        c = self.config()
        test_support.policy.validate(test_support.to_lua(c))
        core, relay = test_support.compile(c)
        self.assertTrue(core)
        self.assertTrue(relay)

    def test_device_ip_must_match_selected_vlan(self):
        c = self.config()
        c["devices"][-1]["ip"] = "192.168.20.101"
        with self.assertRaises(Exception):
            test_support.policy.validate(test_support.to_lua(c))

    def test_firewall_guards_all_managed_interfaces_and_uses_vlan_scope(self):
        c = self.config()
        firewall = test_support.from_lua(
            test_support.policy.firewall(test_support.to_lua(c), "nft")
        )["nft"]
        self.assertIn(
            "iifname @lan_ifaces meta nfproto ipv4 ether saddr @proxy_macs",
            firewall,
        )
        self.assertIn(
            'iifname "eth1.10" ether saddr 02:00:00:00:00:10 ip saddr 192.168.10.101',
            firewall,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
