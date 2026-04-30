#!/bin/sh
set -e
# Встроенный в образ snmp.yml использует SNMPv2 по auth «public_v2» (community задаётся в auths → community).
COMMUNITY="${SNMP_COMMUNITY:-public}"
sed "s/community: public/community: ${COMMUNITY}/g" /etc/snmp_exporter/snmp.yml > /tmp/snmp.yml
exec /bin/snmp_exporter --config.file=/tmp/snmp.yml
