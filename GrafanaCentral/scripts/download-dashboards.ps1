# Download Grafana dashboards for VictoriaMetrics stack.
# Keeps the Docker/cAdvisor dashboard and adds the selected Node Exporter and MikroTik dashboards.

$dashboards = @(
    @{ Id = 10229; File = "victoriametrics.json" }
    @{ Id = 12683; File = "vmagent.json" }
    @{ Id = 14950; File = "vmalert.json" }
    @{ Id = 1860;  File = "node-exporter.json" }
    @{ Id = 14857; File = "mikrotik.json" }
    @{ Id = 13679; File = "mktxp.json" }
    @{ Id = 14282; File = "docker.json" }
)

$targetDir = Join-Path $PSScriptRoot "..\dashboards"
if (-not (Test-Path $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
}

foreach ($dash in $dashboards) {
    $revisionsUrl = "https://grafana.com/api/dashboards/$($dash.Id)/revisions"
    $outputPath = Join-Path $targetDir $dash.File

    try {
        $revisions = Invoke-RestMethod -Uri $revisionsUrl -Method Get
        $latestRevision = ($revisions | Sort-Object -Property revision -Descending | Select-Object -First 1).revision

        if (-not $latestRevision) {
            throw "Cannot resolve latest revision"
        }

        $url = "https://grafana.com/api/dashboards/$($dash.Id)/revisions/$latestRevision/download"
        Write-Host "Downloading dashboard $($dash.Id) revision $latestRevision -> $($dash.File)..."

        $json = Invoke-RestMethod -Uri $url -Method Get
        $jsonStr = $json | ConvertTo-Json -Depth 100 -Compress:$false

        # Replace datasource variable with our provisioned datasource uid
        $jsonStr = $jsonStr -replace '\$\{DS_PROMETHEUS\}', 'victoriametrics'

        Set-Content -Path $outputPath -Value $jsonStr -Encoding UTF8
        Write-Host "  Saved to $outputPath"
    }
    catch {
        Write-Error "Failed to download dashboard $($dash.Id): $_"
    }
}

Write-Host "Done. Restart Grafana or run 'docker compose restart grafana' to load dashboards."
