$ErrorActionPreference = 'Stop'
Push-Location (Join-Path $PSScriptRoot '../frontend/flutter')
try {
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }
    flutter analyze
    if ($LASTEXITCODE -ne 0) { throw 'flutter analyze failed' }
    flutter test
    if ($LASTEXITCODE -ne 0) { throw 'flutter test failed' }
} finally {
    Pop-Location
}
