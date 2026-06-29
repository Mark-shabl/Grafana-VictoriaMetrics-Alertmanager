#!/usr/bin/env bash
# Install safe log retention on the host:
# - Docker container logs are capped by compose logging options.
# - This script configures journald limits and a daily vacuum cron.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-7}"
JOURNAL_MAX_USE="${JOURNAL_MAX_USE:-512M}"
JOURNAL_KEEP_FREE="${JOURNAL_KEEP_FREE:-1G}"
CRON_FILE="/etc/cron.d/monitoring-docker-logs"
JOURNALD_DROPIN_DIR="/etc/systemd/journald.conf.d"
JOURNALD_DROPIN_FILE="${JOURNALD_DROPIN_DIR}/90-monitoring-retention.conf"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root or with sudo." >&2
  exit 1
fi

install -d -m 755 "${JOURNALD_DROPIN_DIR}"
chmod +x "${SCRIPT_DIR}/docker-log-retention.sh"

cat >"${JOURNALD_DROPIN_FILE}" <<EOF
[Journal]
SystemMaxUse=${JOURNAL_MAX_USE}
SystemKeepFree=${JOURNAL_KEEP_FREE}
MaxRetentionSec=${LOG_RETENTION_DAYS}day
EOF

cat >"${CRON_FILE}" <<EOF
# Grafana-VictoriaMetrics stack: vacuum journald; Docker json logs rotate via compose.
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
0 3 * * * root LOG_RETENTION_DAYS=${LOG_RETENTION_DAYS} JOURNAL_MAX_USE=${JOURNAL_MAX_USE} ${SCRIPT_DIR}/docker-log-retention.sh >> /var/log/monitoring-docker-log-retention.log 2>&1
EOF
chmod 644 "${CRON_FILE}"

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart systemd-journald || true
fi

"${SCRIPT_DIR}/docker-log-retention.sh" || true

echo "Installed:"
echo "  ${JOURNALD_DROPIN_FILE}"
echo "  ${CRON_FILE} (daily at 03:00, LOG_RETENTION_DAYS=${LOG_RETENTION_DAYS}, JOURNAL_MAX_USE=${JOURNAL_MAX_USE})"
echo ""
echo "Docker container logs are capped by docker-compose logging options."
echo "Recreate stack containers once to apply those limits:"
echo "  cd ${STACK_DIR} && docker compose up -d --force-recreate"
