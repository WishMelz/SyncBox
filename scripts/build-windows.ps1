$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location (Join-Path $root 'frontend/flutter')
flutter pub get
flutter build windows --release --no-pub
$source = Join-Path $PWD 'build/windows/x64/runner/Release'
$target = Join-Path $root 'dist/SyncBox-windows'
if (Test-Path $target) { Remove-Item $target -Recurse -Force }
New-Item -ItemType Directory -Path $target | Out-Null
Copy-Item "$source/*" $target -Recurse
Write-Host "Windows build: $target"
