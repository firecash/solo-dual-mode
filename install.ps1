param(
  [ValidateSet('download','existing','disabled')][string]$ZkasNode = 'download',
  [ValidateSet('download','existing','disabled')][string]$KaspaNode = 'disabled',
  [string]$ZkasRpc = '127.0.0.1:16810',
  [string]$KaspaRpc = '127.0.0.1:16110',
  [string]$StratumBind = '0.0.0.0:5555',
  [Parameter(Mandatory=$true)][string]$ZkasAddress,
  [string]$KaspaPayAddress = '',
  [string]$InstallDir = "$env:ProgramFiles\ZKas\SoloGateway",
  [string]$DataDir = "$env:ProgramData\ZKas\SoloGateway",
  [string]$ZkasNodeBin = '',
  [string]$KaspaNodeBin = '',
  [string]$BridgeBin = '',
  [string]$ZkasReleaseManifest = $env:ZKAS_RELEASE_MANIFEST_URL,
  [string]$KaspaReleaseManifest = $env:KASPA_RELEASE_MANIFEST_URL,
  [string]$BridgeReleaseManifest = $env:ZKAS_BRIDGE_MANIFEST_URL,
  [switch]$NoStart
)
$ErrorActionPreference = 'Stop'
if (-not $ZkasAddress.StartsWith('zkas:')) { throw '--ZkasAddress must start with zkas:' }
if ($KaspaNode -ne 'disabled' -and [string]::IsNullOrWhiteSpace($KaspaPayAddress)) { throw '--KaspaPayAddress is required when Kaspa is enabled' }
if ($KaspaPayAddress -and -not $KaspaPayAddress.StartsWith('kaspa:')) { throw '--KaspaPayAddress must start with kaspa:' }
function Assert-PortFree([string]$Endpoint) {
  $port = [int]($Endpoint.Split(':')[-1])
  if (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue) { throw "Port $port is already listening; choose another port or use external mode." }
}
if ($ZkasNode -eq 'download') { Assert-PortFree $ZkasRpc }
if ($KaspaNode -eq 'download') { Assert-PortFree $KaspaRpc }
Assert-PortFree $StratumBind
function Install-ManifestAsset([string]$ManifestUrl,[string]$AssetName,[string]$Destination) {
  if ([string]::IsNullOrWhiteSpace($ManifestUrl)) { throw "No signed manifest URL for $AssetName" }
  $m = Invoke-RestMethod -Uri $ManifestUrl -UseBasicParsing
  $platform = $m.assets.PSObject.Properties['windows-x86_64'].Value
  $asset = $platform.PSObject.Properties[$AssetName].Value
  if (-not $asset) { throw "Manifest has no windows-x86_64/$AssetName asset" }
  Invoke-WebRequest -Uri $asset.url -OutFile $Destination -UseBasicParsing
  $actual = (Get-FileHash $Destination -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actual -ne $asset.sha256.ToLowerInvariant()) { Remove-Item $Destination -Force; throw "Checksum mismatch for $AssetName" }
}
if ($ZkasNode -eq 'existing' -and $ZkasNodeBin -and -not (Test-Path $ZkasNodeBin)) { throw "ZKas node binary not found: $ZkasNodeBin" }
if ($KaspaNode -eq 'existing' -and [string]::IsNullOrWhiteSpace($KaspaPayAddress)) { throw 'Existing Kaspa mode requires a Kaspa payout address.' }
if ($KaspaNode -eq 'existing' -and -not (Test-Path $KaspaNodeBin)) { throw "Kaspa node binary not found: $KaspaNodeBin" }
New-Item -ItemType Directory -Force -Path $InstallDir,$DataDir,"$DataDir\zkas-data","$DataDir\kaspa-data","$DataDir\logs" | Out-Null
if ($BridgeBin) { if (-not (Test-Path $BridgeBin)) { throw "Bridge binary not found: $BridgeBin" }; Copy-Item $BridgeBin "$InstallDir\stratum-bridge.exe" -Force }
if ($ZkasNodeBin) { Copy-Item $ZkasNodeBin "$InstallDir\zkas-node.exe" -Force }
if ($KaspaNode -eq 'existing') { Copy-Item $KaspaNodeBin "$InstallDir\kaspad.exe" -Force }
if ($ZkasNode -eq 'download') { Install-ManifestAsset $ZkasReleaseManifest 'zkas-node.exe' "$InstallDir\zkas-node.exe" }
if ($KaspaNode -eq 'download') { Install-ManifestAsset $KaspaReleaseManifest 'kaspad.exe' "$InstallDir\kaspad.exe" }
if (-not $BridgeBin) { Install-ManifestAsset $BridgeReleaseManifest 'stratum-bridge.exe' "$InstallDir\stratum-bridge.exe" }
$cfg = [ordered]@{
  install_dir = $InstallDir
  data_dir = $DataDir
  zkas_rpc = $ZkasRpc
  kaspa_rpc = $(if ($KaspaNode -eq 'disabled') { '' } else { $KaspaRpc })
  stratum_bind = $StratumBind
  zkas_address = $ZkasAddress
  kaspa_pay_address = $KaspaPayAddress
  node_mode = $ZkasNode
  kaspa_mode = $KaspaNode
}
$cfg | ConvertTo-Json | Set-Content -Encoding UTF8 "$DataDir\config.json"
@"
kaspad_address: "$ZkasRpc"
block_wait_time: 1000
print_stats: true
log_to_file: false
health_check_port: "127.0.0.1:18080"
web_dashboard_port: ""
var_diff: true
shares_per_min: 20
var_diff_stats: false
pow2_clamp: true
extranonce_size: 2
coinbase_tag_suffix: "zkas-solo"
merged_kaspa_address: "$(if ($KaspaNode -eq 'disabled') { '' } else { $KaspaRpc })"
merged_kaspa_pay_address: "$KaspaPayAddress"
instances:
  - stratum_port: "$StratumBind"
    min_share_diff: 8192
    prom_port: "127.0.0.1:18114"
    var_diff: true
    shares_per_min: 20
    pow2_clamp: true
    log_to_file: false
"@ | Set-Content -Encoding UTF8 "$DataDir\bridge.yaml"
Write-Host "Configuration written to $DataDir\config.json"
Write-Host 'Use run.ps1 for a foreground run. The signed release downloader/service wrapper is a separate release step.'
if (-not $NoStart) { Write-Host 'No process was started by this bootstrap installer.' }
