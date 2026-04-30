#!/usr/bin/env python3
"""Generate /etc/mktxp/mktxp.conf and credentials.yml from environment (credentials never in INI).

Required: MIKROTIK_API_USER, MIKROTIK_API_PASSWORD.
Optional: see central/.env.example
"""
from __future__ import annotations

import os
from pathlib import Path

import yaml

CRED_PATH = Path("/etc/mktxp/credentials.yml")
CFG_PATH = Path("/etc/mktxp/mktxp.conf")

host = os.environ.get("MIKROTIK_API_HOST", "192.168.88.1").strip()
port = int(os.environ.get("MIKROTIK_API_PORT", "8728"))
use_ssl_raw = os.environ.get("MKTXP_USE_SSL", "False").strip().lower()
use_ssl = use_ssl_raw in ("1", "true", "yes", "on")
plaintext_login_raw = os.environ.get("MKTXP_PLAINTEXT_LOGIN", "True").strip().lower()
plaintext_login = plaintext_login_raw in ("1", "true", "yes", "on")
router_section = os.environ.get("MKTXP_ROUTER_SECTION", "CRS326").strip() or "CRS326"

poe_raw = os.environ.get("MKTXP_POE", "False").strip().lower()
poe_enabled = poe_raw in ("1", "true", "yes", "on")

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

# CRS326-oriented defaults: bridge/switch ports, no Wi‑Fi/CAPsMAN by default.
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
    installed_packages = False
    dhcp = False
    dhcp_lease = False

    connections = True
    connection_stats = False

    interface = True

    route = True
    pool = True
    firewall = True
    neighbor = True
    address_list = None
    dns = False

    ipv6_route = False
    ipv6_pool = False
    ipv6_firewall = False
    ipv6_neighbor = False
    ipv6_address_list = None

    poe = {poe_enabled}
    monitor = True
    netwatch = True
    public_ip = True
    wireless = False
    wireless_clients = False
    capsman = False
    capsman_clients = False
    w60g = False

    eoip = False
    gre = False
    ipip = False
    lte = False
    ipsec = False
    switch_port = True

    kid_control_assigned = False
    kid_control_dynamic = False

    user = True
    queue = True

    bfd = False
    bgp = False
    routing_stats = False
    certificate = False

    container = False

    remote_dhcp_entry = None
    remote_capsman_entry = None

    interface_name_format = name
    check_for_updates = False
"""

CFG_PATH.write_text(ini, encoding="utf-8")
CFG_PATH.chmod(0o600)
