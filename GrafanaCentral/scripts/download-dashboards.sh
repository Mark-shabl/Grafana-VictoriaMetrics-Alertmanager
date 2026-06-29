#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target_dir="$(cd "${script_dir}/.." && pwd)/dashboards"

mkdir -p "${target_dir}"

download_dashboard() {
  local id="$1"
  local file="$2"
  local revision
  local url
  local output="${target_dir}/${file}"

  revision="$(
    curl -fsSL "https://grafana.com/api/dashboards/${id}/revisions" \
      | tr ',' '\n' \
      | sed -n 's/.*"revision"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' \
      | awk 'max < $1 { max = $1 } END { print max }'
  )"

  if [[ -z "${revision}" ]]; then
    printf 'Failed to resolve latest revision for dashboard %s\n' "${id}" >&2
    return 1
  fi

  url="https://grafana.com/api/dashboards/${id}/revisions/${revision}/download"

  printf 'Downloading dashboard %s revision %s -> %s...\n' "${id}" "${revision}" "${file}"
  curl -fsSL "${url}" \
    | sed 's/${DS_PROMETHEUS}/victoriametrics/g' \
    > "${output}"
}

download_dashboard 10229 "victoriametrics.json"
download_dashboard 12683 "vmagent.json"
download_dashboard 14950 "vmalert.json"
download_dashboard 1860 "node-exporter.json"
download_dashboard 14857 "mikrotik.json"
download_dashboard 13679 "mktxp.json"
download_dashboard 14282 "docker.json"

printf 'Done. Restart Grafana or run: docker compose restart grafana\n'
