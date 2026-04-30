#!/usr/bin/env python3
"""Generate /etc/mktxp/mktxp.conf and credentials.yml from environment (credentials never in INI).

Required: MIKROTIK_API_USER, MIKROTIK_API_PASSWORD.
Optional: see central/.env.example — MKTXP_PROFILE=full (default) or crs / minimal / switch.
"""
from __future__ import annotations

import os
from pathlib import Path

import yaml

CRED_PATH = Path("/etc/mktxp/credentials.yml")
CFG_PATH = Path("/etc/mktxp/mktxp.conf")


def env_bool(var: str, default: bool) -> bool:
    raw = os.environ.get(var)
    if raw is None or raw.strip() == "":
        return default
    return raw.strip().lower() in ("1", "true", "yes", "on")


host = os.environ.get("MIKROTIK_API_HOST", "192.168.88.1").strip()
port = int(os.environ.get("MIKROTIK_API_PORT", "8728"))
use_ssl = env_bool("MKTXP_USE_SSL", False)
plaintext_login = env_bool("MKTXP_PLAINTEXT_LOGIN", True)
router_section = os.environ.get("MKTXP_ROUTER_SECTION", "CRS326").strip() or "CRS326"

profile = os.environ.get("MKTXP_PROFILE", "full").strip().lower()
crs_like = profile in ("crs", "minimal", "switch", "light")

user = os.environ.get("MIKROTIK_API_USER", "").strip()
password = os.environ.get("MIKROTIK_API_PASSWORD")
if not user or password is None or password == "":
    raise SystemExit(
        "MIKROTIK_API_USER and MIKROTIK_API_PASSWORD must be set "
        "(e.g. via central/.env); API user needs policy api,read on RouterOS."
    )

CRED_PATH.write_text(
    yaml.safe_dump(
        {"username": user, "password": password},
        default_flow_style=False,
        allow_unicode=True,
    ),
    encoding="utf-8",
)
CRED_PATH.chmod(0o600)

if crs_like:
    poe = env_bool("MKTXP_POE", False)
    dhcp = env_bool("MKTXP_DHCP", False)
    dhcp_lease = env_bool("MKTXP_DHCP_LEASE", False)
    installed_packages = False
    connection_stats = False
    dns = False
    ipv6_route = ipv6_pool = ipv6_firewall = ipv6_neighbor = False
    wireless = wireless_clients = False
    capsman = capsman_clients = False
    w60g = False
    eoip = gre = ipip = lte = ipsec = False
    switch_port = True
    kid_assigned = kid_dynamic = False
    bfd = bgp = routing_stats = certificate = container = False
    check_updates = False
else:
    # full: апстрим-шаблон + все коллекторы, которые там по умолчанию выключены
    poe = env_bool("MKTXP_POE", True)
    dhcp = True
    dhcp_lease = True
    installed_packages = True
    connection_stats = True
    dns = True
    ipv6_route = ipv6_pool = ipv6_firewall = ipv6_neighbor = True
    wireless = wireless_clients = True
    capsman = capsman_clients = True
    w60g = True
    eoip = gre = ipip = lte = ipsec = True
    switch_port = True
    kid_assigned = kid_dynamic = True
    bfd = bgp = routing_stats = certificate = container = True
    check_updates = True

ini = f"""[{router_section}]
    hostname = {host}
    port = {port}
    use_ssl = {use_ssl}

[default]
    enabled = True
    module_only = False
    hostname = localhost
    port = {port}

    credentials_file = /etc/mktxp/credentials.yml

    custom_labels = None

    use_ssl = {use_ssl}
    no_ssl_certificate = False
    ssl_certificate_verify = False
    ssl_check_hostname = True
    ssl_ca_file = ""
    plaintext_login = {plaintext_login}

    health = True
    installed_packages = {installed_packages}
    dhcp = {dhcp}
    dhcp_lease = {dhcp_lease}

    connections = True
    connection_stats = {connection_stats}

    interface = True

    route = True
    pool = True
    firewall = True
    neighbor = True
    address_list = None
    dns = {dns}

    ipv6_route = {ipv6_route}
    ipv6_pool = {ipv6_pool}
    ipv6_firewall = {ipv6_firewall}
    ipv6_neighbor = {ipv6_neighbor}
    ipv6_address_list = None

    poe = {poe}
    monitor = True
    netwatch = True
    public_ip = True
    wireless = {wireless}
    wireless_clients = {wireless_clients}
    capsman = {capsman}
    capsman_clients = {capsman_clients}
    w60g = {w60g}

    eoip = {eoip}
    gre = {gre}
    ipip = {ipip}
    lte = {lte}
    ipsec = {ipsec}
    switch_port = {switch_port}

    kid_control_assigned = {kid_assigned}
    kid_control_dynamic = {kid_dynamic}

    user = True
    queue = True

    bfd = {bfd}
    bgp = {bgp}
    routing_stats = {routing_stats}
    certificate = {certificate}

    container = {container}

    remote_dhcp_entry = None
    remote_capsman_entry = None

    interface_name_format = name
    check_for_updates = {check_updates}
"""

CFG_PATH.write_text(ini, encoding="utf-8")
CFG_PATH.chmod(0o600)
