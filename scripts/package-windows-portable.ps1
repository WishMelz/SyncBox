param(
  [Parameter(Mandatory)][string]$Source,
  [Parameter(Mandatory)][string]$Destination
)
$ErrorActionPreference = 'Stop'
foreach ($file in 'syncbox.exe', 'flutter_windows.dll', 'data/app.so', 'data/icudtl.dat', 'data/flutter_assets') {
  if (!(Test-Path (Join-Path $Source $file))) { throw "Incomplete Flutter release: missing $file" }
}

# Ship the x64 release CRT app-local so users do not need the VC++ installer.
$locator = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$vs = & $locator -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$vs) { throw 'Visual Studio x64 C++ tools not found.' }
$redist = Join-Path $vs 'VC/Redist/MSVC'
$crt = Get-ChildItem $redist -Directory | Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
  Sort-Object { [version]$_.Name } -Descending | ForEach-Object {
    Get-ChildItem (Join-Path $_.FullName 'x64/Microsoft.VC*.CRT') -Directory -ErrorAction SilentlyContinue
  } | Select-Object -First 1
if (!$crt -or !(Test-Path (Join-Path $crt.FullName 'msvcp140.dll'))) { throw 'Visual C++ x64 redistributable DLLs not found.' }
$stage = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
try {
  New-Item -ItemType Directory $stage | Out-Null
  Copy-Item (Join-Path $Source '*') $stage -Recurse
  Copy-Item (Join-Path $crt.FullName '*.dll') $stage -Force
  Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $Destination -Force
} finally {
  if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
}
