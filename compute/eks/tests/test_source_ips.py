"""Offline CIDR checks; optionally compare with the platform's canonical JSON.

RAVION_OIDC_SOURCE_IPS_FILE=/path/to/oidc-source-ips.json python3 tests/test_source_ips.py
"""

import ipaddress
import json
import os
from pathlib import Path
import re
import unittest


def module_source_ips():
    source = (Path(__file__).resolve().parents[1] / "locals.tf").read_text()
    match = re.search(r"ravion_access_source_cidrs\s*=\s*\[([^\]]*)\]", source)
    if match is None:
        raise ValueError("Missing hardcoded ravion_access_source_cidrs local")
    return re.findall(r'"([^"\n]+)"', match.group(1))


def verify_source_ips(actual, canonical):
    if not actual or len(actual) != len(set(actual)):
        raise ValueError("Source CIDRs must be nonempty and unique")
    for value in actual:
        network = ipaddress.ip_network(value, strict=True)
        if network.version != 4 or network.prefixlen != 32:
            raise ValueError("Source CIDRs must be exact IPv4 /32 hosts")
    if set(actual) != set(canonical):
        raise ValueError("Module source CIDRs differ from the platform canonical set")


class SourceIpTests(unittest.TestCase):
    def test_canonical_platform_set(self):
        canonical_path = os.environ.get("RAVION_OIDC_SOURCE_IPS_FILE")
        if not canonical_path:
            self.skipTest("Set RAVION_OIDC_SOURCE_IPS_FILE for cross-repo verification")
        canonical = json.loads(Path(canonical_path).read_text())["sourceIps"]
        verify_source_ips(module_source_ips(), canonical)

    def test_only_exact_ipv4_hosts(self):
        actual = module_source_ips()
        verify_source_ips(actual, actual)

    def test_adjacent_and_unapproved_addresses_are_outside_trust(self):
        networks = [ipaddress.ip_network(value) for value in module_source_ips()]
        denied = [ipaddress.ip_address(value) for value in [
            "0.0.0.0", "10.0.0.1", "127.0.0.1", "192.0.2.1", "::1",
        ]]
        for network in networks:
            denied.extend([network.network_address - 1, network.broadcast_address + 1])
        for address in denied:
            with self.subTest(address=str(address)):
                self.assertFalse(any(address in network for network in networks))

    def test_reject_cidr_broadening_and_set_drift(self):
        canonical = module_source_ips()
        mutations = [
            [],
            canonical + [canonical[0]],
            canonical[:-1],
            canonical + ["192.0.2.1/32"],
            ["0.0.0.0/0"],
            ["35.165.172.0/24"] + canonical[1:],
            ["::/0"],
        ]
        for changed in mutations:
            with self.subTest(cidrs=changed):
                with self.assertRaises(ValueError):
                    verify_source_ips(changed, canonical)


if __name__ == "__main__":
    unittest.main()
