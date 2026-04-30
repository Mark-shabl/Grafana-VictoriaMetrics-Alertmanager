#!/usr/bin/env bash
set -euo pipefail

VM_URL="${VM_URL:-http://127.0.0.1:8428}"

query() {
  local expr="$1"
  curl -fsS --get "${VM_URL}/api/v1/query" --data-urlencode "query=${expr}"
}

check_query() {
  local name="$1"
  local expr="$2"
  local response

  printf 'Checking %-34s ' "${name}..."
  response="$(query "${expr}")"

  if printf '%s' "${response}" | grep -q '"status":"success"' && ! printf '%s' "${response}" | grep -q '"result":\[\]'; then
    printf 'OK\n'
    return 0
  fi

  printf 'MISSING\n'
  printf '  Query: %s\n' "${expr}"
  return 1
}

curl -fsS "${VM_URL}/health" >/dev/null
printf 'VictoriaMetrics health: OK (%s)\n' "${VM_URL}"

check_query "scrape targets" 'up'
check_query "node_exporter target" 'up{job="node_exporter"} == 1'
check_query "cadvisor target" 'up{job="cadvisor"} == 1'
# `up == 1` иногда даёт пустой instant-ответ сразу после рестарта; достаточно факта скрейпа цели.
check_query "mktxp scrape (process_virtual_memory_bytes)" '{__name__="process_virtual_memory_bytes",job="mktxp"}'
check_query "host CPU metrics" 'node_cpu_seconds_total'
check_query "container CPU metrics" 'container_cpu_usage_seconds_total'

printf '\nMonitoring smoke check passed.\n'
