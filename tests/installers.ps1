# Run with: pwsh -NoProfile -File tests/installers.ps1 (or Windows PowerShell).
# Fake gh and byte fixtures only; never downloads or executes a companion.
$ErrorActionPreference = "Stop"
$source = Join-Path (Split-Path -Parent $PSScriptRoot) "install.ps1"
$root = Join-Path ([IO.Path]::GetTempPath()) ("gentle-cc-test-" + [guid]::NewGuid().ToString("N"))
$envNames = @("HOME", "USERPROFILE", "GENTLE_CC_DEST", "GENTLE_CC_VERSION", "PROCESSOR_ARCHITECTURE")
$saved = @{}
foreach ($name in $envNames) { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }

function Assert($Condition, $Message) {
  if (-not $Condition) { throw "assertion failed: $Message" }
}

function Write-Release($Directory, $Version, $Content) {
  New-Item -ItemType Directory -Force -Path $Directory | Out-Null
  $name = "gentle-ai-cc_${Version}_windows_amd64.exe"
  [IO.File]::WriteAllText((Join-Path $Directory $name), $Content)
  $hash = (Get-FileHash (Join-Path $Directory $name) -Algorithm SHA256).Hash.ToLower()
  [IO.File]::WriteAllText((Join-Path $Directory "checksums.txt"), "$hash  $name`n")
}

function Snapshot($Directory) {
  return ((Get-ChildItem -LiteralPath $Directory -File | Sort-Object Name | ForEach-Object {
    $_.Name + ":" + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
  }) -join "`n")
}

# A command-shaped fake also sets the native exit-status variable: a failing gh
# may have left apparently complete bytes, which the installer must not trust.
function global:gh {
  $destination = $args[([array]::IndexOf($args, "-D") + 1)]
  $global:DownloadDirs += $destination
  Write-Release $destination $env:GENTLE_CC_VERSION "downloaded-$env:GENTLE_CC_VERSION"
  $assetPath = Join-Path $destination "gentle-ai-cc_$($env:GENTLE_CC_VERSION)_windows_amd64.exe"
  if ($global:DownloadMode -eq "mismatch") { [IO.File]::WriteAllText($assetPath, "tampered") }
  if ($global:DownloadMode -eq "incomplete") { Remove-Item -LiteralPath $assetPath }
  $global:LASTEXITCODE = if ($global:DownloadMode -eq "gh-failure") { 23 } else { 0 }
}

try {
  New-Item -ItemType Directory -Path $root | Out-Null
  $env:HOME = $root
  $env:USERPROFILE = $root
  $env:PROCESSOR_ARCHITECTURE = "AMD64"
  $global:DownloadDirs = @()
  foreach ($case in @("local", "local-mismatch", "stale", "missing-entry", "missing-asset",
                       "mismatch", "incomplete", "gh-failure", "next-version")) {
    $fixture = Join-Path $root $case
    New-Item -ItemType Directory -Path $fixture | Out-Null
    Copy-Item -LiteralPath $source -Destination (Join-Path $fixture "install.ps1")
    $dist = Join-Path $fixture "dist"
    $env:GENTLE_CC_VERSION = if ($case -eq "next-version") { "v2" } else { "v1" }
    $env:GENTLE_CC_DEST = Join-Path $fixture "dest"
    New-Item -ItemType Directory -Path $env:GENTLE_CC_DEST | Out-Null
    $installed = Join-Path $env:GENTLE_CC_DEST "gentle-ai-cc.exe"
    [IO.File]::WriteAllText($installed, "old binary")
    $localVersion = if ($case -in @("local", "local-mismatch", "missing-entry", "missing-asset")) { "v1" } else { "old" }
    Write-Release $dist $localVersion "local bytes"
    $localAsset = Join-Path $dist "gentle-ai-cc_${localVersion}_windows_amd64.exe"
    if ($case -eq "local-mismatch") { [IO.File]::WriteAllText($localAsset, "tampered") }
    if ($case -eq "missing-entry") { [IO.File]::WriteAllText((Join-Path $dist "checksums.txt"), "") }
    if ($case -eq "missing-asset") { Remove-Item -LiteralPath $localAsset }
    $before = Snapshot $dist
    $callsBefore = $global:DownloadDirs.Count
    $global:DownloadMode = $case
    $failure = $null
    try { & (Join-Path $fixture "install.ps1") } catch { $failure = $_.Exception.Message }
    $shouldFail = $case -in @("local-mismatch", "mismatch", "incomplete", "gh-failure")
    Assert (($null -ne $failure) -eq $shouldFail) "$case failure outcome: $failure"
    if ($case -in @("local-mismatch", "mismatch")) {
      Assert ($failure -like "checksum mismatch for *") "$case checksum rejection"
    }
    if ($case -eq "gh-failure") {
      Assert ($failure -eq "gh release download failed (exit 23)") "native exit status"
    }
    $expected = if ($shouldFail) { "old binary" } elseif ($case -eq "local") { "local bytes" } else { "downloaded-$env:GENTLE_CC_VERSION" }
    Assert (([IO.File]::ReadAllText($installed)) -eq $expected) "$case destination bytes"
    Assert ((Snapshot $dist) -eq $before) "$case never mutates local dist"
    $expectedCalls = if ($case -in @("local", "local-mismatch")) { 0 } else { 1 }
    Assert (($global:DownloadDirs.Count - $callsBefore) -eq $expectedCalls) "$case download route"
    foreach ($directory in $global:DownloadDirs) {
      Assert (-not (Test-Path -LiteralPath $directory)) "$case owned staging cleaned"
    }
    Write-Host "PASS: $case"
  }
  Assert (($global:DownloadDirs | Select-Object -Unique).Count -eq $global:DownloadDirs.Count) "fresh staging for each download/version"
} finally {
  foreach ($name in $envNames) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
  Remove-Item Function:\gh
  if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
