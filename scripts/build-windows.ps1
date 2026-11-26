$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location (Join-Path $root 'frontend/flutter')
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
flutter build windows --release --no-pub
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$source = Join-Path $PWD 'build/windows/x64/runner/Release'
$target = Join-Path $root 'dist/SyncBox-windows'
if (Test-Path $target) { Remove-Item $target -Recurse -Force }
New-Item -ItemType Directory -Path $target | Out-Null
Copy-Item "$source/*" $target -Recurse
Write-Host "Windows build: $target"
$portable = Join-Path $root 'dist/SyncBox-Windows-x64-Portable.zip'
& (Join-Path $PSScriptRoot 'package-windows-portable.ps1') -Source $target -Destination $portable
Write-Host "Windows portable ZIP: $portable"
