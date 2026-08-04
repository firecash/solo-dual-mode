param([string]$Config = "$env:ProgramData\ZKas\SoloGateway\config.json")
$ErrorActionPreference = 'Stop'
$c = Get-Content $Config -Raw | ConvertFrom-Json
$root = $c.install_dir
$bridge = Join-Path $root 'stratum-bridge.exe'
if (-not (Test-Path $bridge)) { throw "Missing bridge binary: $bridge" }
if ($c.node_mode -eq 'download') {
  $node = Join-Path $root 'zkas-node.exe'
  if (-not (Test-Path $node)) { throw "Missing managed node binary: $node" }
  $nodeProc = Start-Process -FilePath $node -ArgumentList @('--appdir', (Join-Path $c.data_dir 'zkas-data'), '--rpclisten', $c.zkas_rpc, '--listen', '0.0.0.0:16811', '--utxoindex', '--disable-upnp', '--yes') -PassThru
  Write-Host "ZKas node PID $($nodeProc.Id) started"
}
if ($c.kaspa_mode -eq 'download') {
  $parent = Join-Path $root 'kaspad.exe'
  if (-not (Test-Path $parent)) { throw "Missing managed Kaspa binary: $parent" }
  $parentProc = Start-Process -FilePath $parent -ArgumentList @('--appdir', (Join-Path $c.data_dir 'kaspa-data'), '--rpclisten', $c.kaspa_rpc, '--listen', '0.0.0.0:16111', '--utxoindex', '--disable-upnp', '--yes') -PassThru
  Write-Host "Kaspa parent PID $($parentProc.Id) started"
}
if ($c.kaspa_mode -ne 'disabled') {
  $env:ZKAS_MERGED_MINING = '1'
  $env:ZKAS_KASPA_NODE = $c.kaspa_rpc
  $env:ZKAS_KASPA_PAY = $c.kaspa_pay_address
}
$bridgeProc = Start-Process -FilePath $bridge -ArgumentList @('--node-mode','external','--config',(Join-Path $c.data_dir 'bridge.yaml')) -PassThru
Write-Host "Bridge PID $($bridgeProc.Id) started; Stratum is configured by the generated bridge config."
Wait-Process -Id $bridgeProc.Id
