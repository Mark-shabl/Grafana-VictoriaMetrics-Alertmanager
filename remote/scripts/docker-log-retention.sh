#!/usr/bin/env bash
# Daily retention helper for systemd journal only.
# Docker json-file logs are intentionally NOT touched here:
# Docker must own /var/lib/docker/containers/*/*-json.log and already rotates
# them via max-size/max-file in docker-compose.yml.
set -euo pipefail

LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-7}"
JOURNAL_MAX_USE="${JOURNAL_MAX_USE:-512M}"

if ! [[ "${LOG_RETENTION_DAYS}" =~ ^[0-9]+$ ]] || [[ "${LOG_RETENTION_DAYS}" -lt 1 ]]; then
  echo "LOG_RETENTION_DAYS must be a positive integer, got: ${LOG_RETENTION_DAYS}" >&2
  exit 1
fi

echo "Journal retention: ${LOG_RETENTION_DAYS} day(s), max ${JOURNAL_MAX_USE}"

if command -v journalctl >/dev/null 2>&1; then
  journalctl --vacuum-time="${LOG_RETENTION_DAYS}d" || true
  journalctl --vacuum-size="${JOURNAL_MAX_USE}" || true
  journalctl --disk-usage || true
fi

echo "Done."
