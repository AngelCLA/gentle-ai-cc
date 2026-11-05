# install.ps1 — Windows installer for the Command Code companion of gentle-ai.
#
# Private repository: anonymous download does not work. This script prefers:
#   1. a local .\dist directory (artifacts from gentle-cc-release.sh)
#   2. an authenticated release download via `gh`
#
# Usage (from a clone):
#   powershell -ExecutionPolicy Bypass -File .\install.ps1
#
# Env:
#   GENTLE_CC_VERSION     release tag (default 4.3.1-cc.1)
#   GENTLE_CC_DEST        install dir  (default $env:LOCALAPPDATA\gentle-cc)
#   GENTLE_CC_OWNER_REPO  owner/repo   (default AngelCLA/gentle-ai-cc)
$ErrorActionPreference = "Stop"

$Version   = if ($env:GENTLE_CC_VERSION)    { $env:GENTLE_CC_VERSION }    else { "4.3.1-cc.1" }
$OwnerRepo = if ($env:GENTLE_CC_OWNER_REPO) { $env:GENTLE_CC_OWNER_REPO } else { "AngelCLA/gentle-ai-cc" }
$Dest      = if ($env:GENTLE_CC_DEST)       { $env:GENTLE_CC_DEST }       else { Join-Path $env:LOCALAPPDATA "gentle-cc" }

$arch = switch ($env:PROCESSOR_ARCHITECTURE) {
  "AMD64" { "amd64" }
  "ARM64" { "arm64" }
  default { throw "unsupported architecture: $env:PROCESSOR_ARCHITECTURE" }
}
$asset = "gentle-ai-cc_${Version}_windows_${arch}.exe"

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$distDir = Join-Path $here "dist"

New-Item -ItemType Directory -Force -Path $Dest | Out-Null

if (-not (Test-Path (Join-Path $distDir "checksums.txt"))) {
  if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "no local dist\ and no 'gh' on PATH. Run gentle-cc-release.sh first, or install gh and authenticate."
  }
  Write-Host "downloading release $Version from $OwnerRepo via gh ..."
  gh release download $Version -R $OwnerRepo -D $distDir
}

$manifest = Get-Content (Join-Path $distDir "checksums.txt")
$expected = ($manifest | Where-Object { $_ -match "\s\*?$([regex]::Escape($asset))$" } | Select-Object -First 1) -split '\s+' | Select-Object -First 1
if (-not $expected) { throw "no checksum entry for $asset" }

$actual = (Get-FileHash (Join-Path $distDir $asset) -Algorithm SHA256).Hash.ToLower()
if ($actual -ne $expected.ToLower()) {
  throw "checksum mismatch for $asset: expected $expected got $actual"
}
Write-Host "checksum OK ($asset): $actual"

$binPath = Join-Path $Dest "gentle-ai-cc.exe"
Copy-Item (Join-Path $distDir $asset) $binPath -Force
Write-Host "installed: $binPath"

# The gentle-cc wrapper is a bash script; on Windows use it via Git Bash or WSL,
# or invoke the companion directly:
Write-Host ""
Write-Host "next:"
Write-Host "  $binPath version"
Write-Host "  $binPath install --agent command-code --preset full-gentleman"
Write-Host ""
Write-Host "note: the gentle-cc wrapper is bash-only. On Windows, run it under Git Bash"
Write-Host "      or WSL, or call the companion binary directly as above."
