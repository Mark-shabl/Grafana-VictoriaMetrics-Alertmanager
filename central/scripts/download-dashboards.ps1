# Download Grafana dashboards for VictoriaMetrics stack
# Dashboards: VictoriaMetrics single (10229), vmagent (12683), vmalert (14950), Node Exporter (1860)

$dashboards = @(
    @{ Id = 10229; File = "victoriametrics.json" }
    @{ Id = 12683; File = "vmagent.json" }
    @{ Id = 14950; File = "vmalert.json" }
    @{ Id = 1860;  File = "node-exporter.json" }
    @{ Id = 14282; File = "docker.json" }
)

$targetDir = Join-Path $PSScriptRoot "..\dashboards"
if (-not (Test-Path $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
}

foreach ($dash in $dashboards) {
    $url = "https://grafana.com/api/dashboards/$($dash.Id)/revisions/1/download"
    $outputPath = Join-Path $targetDir $dash.File

    Write-Host "Downloading dashboard $($dash.Id) -> $($dash.File)..."
    try {
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
