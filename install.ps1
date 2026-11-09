# install.ps1 — Windows installer for the Command Code companion of gentle-ai.
#
# Public release assets: this script prefers:
#   1. a complete local native pair in .\dist (from gentle-cc-release.sh)
#   2. an authenticated release download via `gh` when it is available
#   3. the public HTTPS release URL, which needs no `gh`
#
# Usage (from a clone):
#   powershell -ExecutionPolicy Bypass -File .\install.ps1
#
# Env:
#   GENTLE_CC_VERSION     release tag (default 4.3.1-cc.4)
#   GENTLE_CC_DEST        install dir  (default $env:LOCALAPPDATA\gentle-cc)
#   GENTLE_CC_OWNER_REPO  owner/repo   (default AngelCLA/gentle-ai-cc)
# 4.3.1-cc.4 is the native release; 4.3.1-cc.1 is the legacy wrapper.
# Runtime needs no Bash/Python; packaging needs Go.
# Controlled publication failures roll back changed files, not a crash-safe or
# pair-atomic transaction. Use an exclusively controlled destination.
$ErrorActionPreference = "Stop"

$Version   = if ($env:GENTLE_CC_VERSION)    { $env:GENTLE_CC_VERSION }    else { "4.3.1-cc.4" }
$OwnerRepo = if ($env:GENTLE_CC_OWNER_REPO) { $env:GENTLE_CC_OWNER_REPO } else { "AngelCLA/gentle-ai-cc" }
$Dest      = if ($env:GENTLE_CC_DEST)       { $env:GENTLE_CC_DEST }       else { Join-Path $env:LOCALAPPDATA "gentle-cc" }

$arch = switch ($env:PROCESSOR_ARCHITECTURE) {
  "AMD64" { "amd64" }
  "ARM64" { "arm64" }
  default { throw "unsupported architecture: $env:PROCESSOR_ARCHITECTURE" }
}
$asset = "gentle-ai-cc_${Version}_windows_${arch}.exe"
$wrapperAsset = "gentle-cc_${Version}_windows_${arch}.exe"
$artifacts = [ordered]@{ "gentle-ai-cc.exe" = $asset; "gentle-cc.exe" = $wrapperAsset }

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$distDir = Join-Path $here "dist"

function Get-ExpectedChecksum($Directory, $Name) {
  $manifestPath = Join-Path $Directory "checksums.txt"
  if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { return $null }
  $entry = Get-Content -LiteralPath $manifestPath |
    Where-Object { $_ -match "\s\*?$([regex]::Escape($Name))$" } |
    Select-Object -First 1
  if ($entry) { return ($entry -split '\s+')[0] }
  return $null
}

function Test-SafeDestination($Path) {
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  return (-not $item -or (-not $item.PSIsContainer -and
    -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)))
}

$ownedTemp = $null
$publication = $null
$changed = @()
try {
  # An incomplete pair must use entirely fresh authenticated staging, not a mix.
  $complete = $true
  foreach ($name in $artifacts.Values) {
    if (-not ((Test-Path -LiteralPath (Join-Path $distDir $name) -PathType Leaf) -and
        (Get-ExpectedChecksum $distDir $name))) { $complete = $false }
  }
  if (-not $complete) {
    # An incomplete pair must use entirely fresh staging, never a mix with dist.
    $downloadDir = Join-Path ([IO.Path]::GetTempPath()) ("gentle-cc-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $downloadDir | Out-Null
    $ownedTemp = $downloadDir
    $distDir = $downloadDir
    $ghReady = $false
    if (Get-Command gh -ErrorAction SilentlyContinue) {
      # Windows PowerShell 5.1 promotes redirected native stderr under Stop;
      # authentication failure is expected and should select public HTTPS.
      $previousErrorActionPreference = $ErrorActionPreference
      try {
        $ErrorActionPreference = "Continue"
        gh auth status *> $null
        $ghReady = ($LASTEXITCODE -eq 0)
      } finally {
        $ErrorActionPreference = $previousErrorActionPreference
      }
    }
    $downloaded = $false
    if ($ghReady) {
      Write-Host "downloading release $Version from $OwnerRepo via gh ..."
      gh release download $Version -R $OwnerRepo -D $distDir
      if ($LASTEXITCODE -eq 0) {
        $downloaded = $true
      } else {
        Write-Warning "gh release download failed (exit $LASTEXITCODE); trying the public release URL"
      }
    }
    if (-not $downloaded) {
      $base = "https://github.com/$OwnerRepo/releases/download/$Version"
      Write-Host "downloading release $Version from $base ..."
      foreach ($name in @($artifacts.Values) + "checksums.txt") {
        try {
          Invoke-WebRequest -Uri "$base/$name" -OutFile (Join-Path $distDir $name) -UseBasicParsing -ErrorAction Stop
        } catch {
          throw "download failed for ${name}: $($_.Exception.Message)"
        }
      }
    }
  }

  # Validate every requested artifact before any destination write.
  foreach ($name in $artifacts.Values) {
    $expected = Get-ExpectedChecksum $distDir $name
    if (-not $expected) { throw "no checksum entry for $name" }
    $actual = (Get-FileHash -LiteralPath (Join-Path $distDir $name) -Algorithm SHA256).Hash.ToLower()
    if ($actual -ne $expected.ToLower()) {
      throw "checksum mismatch for ${name}: expected $expected got $actual"
    }
    Write-Host "checksum OK ($name): $actual"
  }
  foreach ($name in $artifacts.Keys) {
    $path = Join-Path $Dest $name
    if (-not (Test-SafeDestination $path)) { throw "unsafe destination: $path" }
  }
  $directory = Get-Item -LiteralPath $Dest -Force -ErrorAction SilentlyContinue
  if ($directory -and (-not $directory.PSIsContainer -or
      ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint))) {
    throw "unsafe destination directory: $Dest"
  }
  New-Item -ItemType Directory -Force -Path $Dest | Out-Null
  $publication = Join-Path $Dest (".gentle-cc-install." + [guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Path $publication | Out-Null
  try {
    foreach ($name in $artifacts.Keys) {
      Copy-Item -LiteralPath (Join-Path $distDir $artifacts[$name]) -Destination (Join-Path $publication "new-$name")
      $path = Join-Path $Dest $name
      if (Test-Path -LiteralPath $path) {
        Copy-Item -LiteralPath $path -Destination (Join-Path $publication "old-$name")
      }
    }
    foreach ($name in $artifacts.Keys) {
      $path = Join-Path $Dest $name
      if (-not (Test-SafeDestination $path)) { throw "unsafe destination: $path" }
      Move-Item -LiteralPath (Join-Path $publication "new-$name") -Destination $path -Force
      $changed += $name
    }
  } catch {
    $publicationError = $_
    $restoreFailed = $false
    foreach ($name in $changed) {
      $path = Join-Path $Dest $name
      try {
        if (-not (Test-SafeDestination $path)) { throw "unsafe destination: $path" }
        $backup = Join-Path $publication "old-$name"
        if (Test-Path -LiteralPath $backup) { Move-Item -LiteralPath $backup -Destination $path -Force }
        else { Remove-Item -LiteralPath $path -Force }
      } catch {
        $restoreFailed = $true
        Write-Warning "restoration failed for $path"
      }
    }
    if ($restoreFailed) {
      Write-Warning "backups retained at $publication; manual recovery required"
      $publication = $null # Do not discard recovery evidence in finally.
    }
    throw $publicationError
  }
  $binPath = Join-Path $Dest "gentle-ai-cc.exe"
  $wrapperPath = Join-Path $Dest "gentle-cc.exe"
  Write-Host "installed: $binPath"
  Write-Host "installed: $wrapperPath"
} finally {
  if ($publication) { Remove-Item -LiteralPath $publication -Recurse -Force }
  if ($ownedTemp) { Remove-Item -LiteralPath $ownedTemp -Recurse -Force }
}

# The native pair needs no runtime interpreter. Not pair-atomic or crash-safe.
Write-Host ""
Write-Host "next:"
Write-Host "  $binPath version"
Write-Host "  $wrapperPath install --preset full-gentleman"
Write-Host "  $wrapperPath sync"
Write-Host ""
Write-Host "Native wrapper runtime requires neither Bash nor Python."
Write-Host "Direct binary calls skip shared-state cleanup; official sync may fail."
Write-Host "Do not run direct binary writes concurrently with the wrapper or each other."
Write-Host "See README: The shared-state detail."
