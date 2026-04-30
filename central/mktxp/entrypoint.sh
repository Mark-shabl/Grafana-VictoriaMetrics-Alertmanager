#!/bin/sh
set -e
mkdir -p /etc/mktxp

python3 /render-config.py
chown mktxp:mktxp /etc/mktxp/mktxp.conf /etc/mktxp/credentials.yml 2>/dev/null || true

# Без явного каталога MKTXP берёт конфиг из ~/mktxp (в образе — /home/mktxp/mktxp), а не из /etc/mktxp.
exec su mktxp -s /bin/sh -c "exec mktxp --cfg-dir /etc/mktxp export"
