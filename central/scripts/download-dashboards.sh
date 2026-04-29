#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target_dir="$(cd "${script_dir}/.." && pwd)/dashboards"

mkdir -p "${target_dir}"

download_dashboard() {
  local id="$1"
  local file="$2"
  local url="https://grafana.com/api/dashboards/${id}/revisions/1/download"
  local output="${target_dir}/${file}"

  printf 'Downloading dashboard %s -> %s...\n' "${id}" "${file}"
  curl -fsSL "${url}" \
    | sed 's/${DS_PROMETHEUS}/victoriametrics/g' \
    > "${output}"
}

download_dashboard 10229 "victoriametrics.json"
download_dashboard 12683 "vmagent.json"
download_dashboard 14950 "vmalert.json"
download_dashboard 1860 "node-exporter.json"
download_dashboard 24458 "envoy-downstream.json"
download_dashboard 14282 "docker.json"

printf 'Done. Restart Grafana or run: docker compose restart grafana\n'
