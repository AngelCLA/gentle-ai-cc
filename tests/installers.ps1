# Run with: pwsh -NoProfile -File tests/installers.ps1 (or Windows PowerShell).
# Fake gh/Invoke-WebRequest and byte fixtures only; never downloads or executes a
# companion.
$ErrorActionPreference = "Stop"
$source = Join-Path (Split-Path -Parent $PSScriptRoot) "install.ps1"
$root = Join-Path ([IO.Path]::GetTempPath()) ("gentle-cc-test-" + [guid]::NewGuid().ToString("N"))
$envNames = @("HOME", "USERPROFILE", "GENTLE_CC_DEST", "GENTLE_CC_VERSION", "GENTLE_CC_OWNER_REPO", "PROCESSOR_ARCHITECTURE", "PATH")
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
  $wrapper = "gentle-cc_${Version}_windows_amd64.exe"
  [IO.File]::WriteAllText((Join-Path $Directory $wrapper), "wrapper-$Content")
  $wrapperHash = (Get-FileHash (Join-Path $Directory $wrapper) -Algorithm SHA256).Hash.ToLower()
  [IO.File]::WriteAllText((Join-Path $Directory "checksums.txt"), "$hash  $name`n$wrapperHash  $wrapper`n")
}

function Snapshot($Directory) {
  return ((Get-ChildItem -LiteralPath $Directory -File | Sort-Object Name | ForEach-Object {
    $_.Name + ":" + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
  }) -join "`n")
}

# A command-shaped fake also sets the native exit-status variable: a failing gh
# may have left apparently complete bytes, which the installer must not trust.
function global:gh {
  if ($args[0] -eq "auth") {
    $global:LASTEXITCODE = if ($global:AuthMode -eq "unauth") { 1 } else { 0 }
    return
  }
  $destination = $args[([array]::IndexOf($args, "-D") + 1)]
  $global:DownloadDirs += $destination
  Write-Release $destination $env:GENTLE_CC_VERSION "downloaded-$env:GENTLE_CC_VERSION"
  $assetPath = Join-Path $destination "gentle-ai-cc_$($env:GENTLE_CC_VERSION)_windows_amd64.exe"
  if ($global:DownloadMode -eq "mismatch") { [IO.File]::WriteAllText($assetPath, "tampered") }
  if ($global:DownloadMode -eq "incomplete") { Remove-Item -LiteralPath $assetPath }
  $wrapperPath = Join-Path $destination "gentle-cc_$($env:GENTLE_CC_VERSION)_windows_amd64.exe"
  if ($global:DownloadMode -eq "wrapper-mismatch") { [IO.File]::WriteAllText($wrapperPath, "tampered") }
  if ($global:DownloadMode -eq "wrapper-incomplete") { Remove-Item -LiteralPath $wrapperPath }
  $global:LASTEXITCODE = if ($global:DownloadMode -eq "gh-failure") { 23 } else { 0 }
}

try {
  New-Item -ItemType Directory -Path $root | Out-Null
  $env:HOME = $root
  $env:USERPROFILE = $root
  $env:PROCESSOR_ARCHITECTURE = "AMD64"
  $env:GENTLE_CC_OWNER_REPO = "fixture/repo"
  $OwnerRepo = $env:GENTLE_CC_OWNER_REPO
  $global:DownloadDirs = @()
  foreach ($case in @("local", "local-mismatch", "stale", "missing-entry", "missing-asset",
                       "mismatch", "incomplete", "next-version", "wrapper-mismatch",
                       "wrapper-incomplete", "local-wrapper-missing", "local-wrapper-entry", "local-wrapper-mismatch")) {
    $fixture = Join-Path $root $case
    New-Item -ItemType Directory -Path $fixture | Out-Null
    Copy-Item -LiteralPath $source -Destination (Join-Path $fixture "install.ps1")
    $dist = Join-Path $fixture "dist"
    $env:GENTLE_CC_VERSION = if ($case -eq "next-version") { "v2" } else { "v1" }
    $env:GENTLE_CC_DEST = Join-Path $fixture "dest"
    New-Item -ItemType Directory -Path $env:GENTLE_CC_DEST | Out-Null
    $installed = Join-Path $env:GENTLE_CC_DEST "gentle-ai-cc.exe"
    [IO.File]::WriteAllText($installed, "old binary")
    $installedWrapper = Join-Path $env:GENTLE_CC_DEST "gentle-cc.exe"
    [IO.File]::WriteAllText($installedWrapper, "old wrapper")
    $localVersion = if ($case -in @("local", "local-mismatch", "missing-entry", "missing-asset",
        "local-wrapper-missing", "local-wrapper-entry", "local-wrapper-mismatch")) { "v1" } else { "old" }
    Write-Release $dist $localVersion "local bytes"
    $localAsset = Join-Path $dist "gentle-ai-cc_${localVersion}_windows_amd64.exe"
    if ($case -eq "local-mismatch") { [IO.File]::WriteAllText($localAsset, "tampered") }
    if ($case -eq "missing-entry") { [IO.File]::WriteAllText((Join-Path $dist "checksums.txt"), "") }
    if ($case -eq "missing-asset") { Remove-Item -LiteralPath $localAsset }
    $localWrapper = Join-Path $dist "gentle-cc_${localVersion}_windows_amd64.exe"
    if ($case -eq "local-wrapper-missing") { Remove-Item -LiteralPath $localWrapper }
    if ($case -eq "local-wrapper-entry") {
      $line = (Get-Content (Join-Path $dist "checksums.txt"))[0]
      [IO.File]::WriteAllText((Join-Path $dist "checksums.txt"), "$line`n")
    }
    if ($case -eq "local-wrapper-mismatch") { [IO.File]::WriteAllText($localWrapper, "tampered") }
    $before = Snapshot $dist
    $callsBefore = $global:DownloadDirs.Count
    $global:DownloadMode = $case
    $failure = $null
    $output = @()
    try { $output = @(& (Join-Path $fixture "install.ps1") 6>&1) } catch { $failure = $_.Exception.Message }
    $shouldFail = $case -in @("local-mismatch", "mismatch", "incomplete",
        "wrapper-mismatch", "wrapper-incomplete", "local-wrapper-mismatch")
    Assert (($null -ne $failure) -eq $shouldFail) "$case failure outcome: $failure"
    if ($case -in @("local-mismatch", "mismatch", "wrapper-mismatch", "local-wrapper-mismatch")) {
      Assert ($failure -like "checksum mismatch for *") "$case checksum rejection"
    }
    $expected = if ($shouldFail) { "old binary" } elseif ($case -eq "local") { "local bytes" } else { "downloaded-$env:GENTLE_CC_VERSION" }
    Assert (([IO.File]::ReadAllText($installed)) -eq $expected) "$case destination bytes"
    $expectedWrapper = if ($shouldFail) { "old wrapper" } else { "wrapper-$expected" }
    Assert (([IO.File]::ReadAllText($installedWrapper)) -eq $expectedWrapper) "$case wrapper bytes"
    Assert ((Snapshot $dist) -eq $before) "$case never mutates local dist"
    $expectedCalls = if ($case -in @("local", "local-mismatch", "local-wrapper-mismatch")) { 0 } else { 1 }
    Assert (($global:DownloadDirs.Count - $callsBefore) -eq $expectedCalls) "$case download route"
    foreach ($directory in $global:DownloadDirs) {
      Assert (-not (Test-Path -LiteralPath $directory)) "$case owned staging cleaned"
    }
    if (-not $shouldFail) {
      $guidance = $output -join "`n"
      Assert ($guidance.Contains("$installedWrapper install --preset full-gentleman")) "$case native invocation"
      $expectedOutput = @()
      if ($expectedCalls) { $expectedOutput += "downloading release $env:GENTLE_CC_VERSION from $OwnerRepo via gh ..." }
      foreach ($pair in @(@("gentle-ai-cc", $installed), @("gentle-cc", $installedWrapper))) {
        $name = "$($pair[0])_$($env:GENTLE_CC_VERSION)_windows_amd64.exe"
        $hash = (Get-FileHash -LiteralPath $pair[1] -Algorithm SHA256).Hash.ToLower()
        $expectedOutput += "checksum OK (${name}): $hash"
      }
      $expectedOutput += @("installed: $installed", "installed: $installedWrapper", "", "next:",
        "  $installed version", "  $installedWrapper install --preset full-gentleman", "  $installedWrapper sync", "",
        "Native wrapper runtime requires neither Bash nor Python.",
        "Direct binary calls skip shared-state cleanup; official sync may fail.",
        "Do not run direct binary writes concurrently with the wrapper or each other.", "See README: The shared-state detail.")
      Assert ($guidance -eq ($expectedOutput -join "`n")) "$case exact success output"
    }
    Write-Host "PASS: $case"
  }
  Assert (($global:DownloadDirs | Select-Object -Unique).Count -eq $global:DownloadDirs.Count) "fresh staging for each download/version"
  # Public HTTPS fallback: no gh, unauthenticated gh, or a failing gh download.
  function global:Invoke-WebRequest {
    [CmdletBinding()]
    param([string]$Uri, [string]$OutFile, [switch]$UseBasicParsing)
    $name = ($Uri -split '/')[-1]
    $global:HttpDirs += (Split-Path -Parent $OutFile)
    Copy-Item -LiteralPath (Join-Path $global:ReleaseDir $name) -Destination $OutFile
  }
  foreach ($public in @(
      @{ Name = "public-gh-unauth"; Gh = "unauth"; Missing = "" },
      @{ Name = "public-default-version"; Gh = "none"; Missing = ""; Default = $true })) {
    $fixture = Join-Path $root $public.Name
    New-Item -ItemType Directory -Path $fixture | Out-Null
    Copy-Item -LiteralPath $source -Destination (Join-Path $fixture "install.ps1")
    $version = if ($public.Default) { "4.3.1-cc.2" } else { "v9" }
    if ($public.Default) { Remove-Item Env:GENTLE_CC_VERSION -ErrorAction SilentlyContinue }
    else { $env:GENTLE_CC_VERSION = $version }
    $env:PATH = "$env:SystemRoot\System32;$env:SystemRoot"
    $env:GENTLE_CC_DEST = Join-Path $fixture "dest"
    New-Item -ItemType Directory -Path $env:GENTLE_CC_DEST | Out-Null
    foreach ($name in @("gentle-ai-cc.exe", "gentle-cc.exe")) {
      [IO.File]::WriteAllText((Join-Path $env:GENTLE_CC_DEST $name), "old-$name")
    }
    $global:ReleaseDir = Join-Path $fixture "release"
    Write-Release $global:ReleaseDir $version "public-$($public.Name)"
    $global:HttpDirs = @()
    if (Test-Path Function:\gh) { Remove-Item Function:\gh }
    $global:AuthMode = $public.Gh
    if ($public.Gh -ne "none") {
      function global:gh {
        if ($args[0] -eq "auth") {
          $global:LASTEXITCODE = if ($global:AuthMode -eq "unauth") { 1 } else { 0 }
          return
        }
        $global:LASTEXITCODE = if ($global:AuthMode -eq "failure") { 23 } else { 0 }
      }
    }
    $failure = $null
    $output = @()
    try { $output = @(& (Join-Path $fixture "install.ps1") 6>&1) } catch { $failure = $_.Exception.Message }
    Assert ($null -eq $failure) "$($public.Name) outcome: $failure"
    Assert (([IO.File]::ReadAllText((Join-Path $env:GENTLE_CC_DEST "gentle-ai-cc.exe"))) -eq "public-$($public.Name)") "$($public.Name) binary bytes"
    Assert (([IO.File]::ReadAllText((Join-Path $env:GENTLE_CC_DEST "gentle-cc.exe"))) -eq "wrapper-public-$($public.Name)") "$($public.Name) wrapper bytes"
    Assert (($output -join "`n").Contains("downloading release $version from https://github.com/fixture/repo/releases/download/$version ...")) "$($public.Name) announcement"
    foreach ($directory in $global:HttpDirs) { Assert (-not (Test-Path -LiteralPath $directory)) "$($public.Name) staging cleaned" }
    Write-Host "PASS: $($public.Name)"
  }
  if (Test-Path Function:\Invoke-WebRequest) { Remove-Item Function:\Invoke-WebRequest }
  if (Test-Path Function:\gh) { Remove-Item Function:\gh }
  # Public publication failures: snapshots happen before writes; second rename
  # failure restores the first artifact, including an initially absent artifact.
  function global:Copy-Item {
    [CmdletBinding()]
    param([string]$LiteralPath, [string]$Destination, [switch]$Force)
    if ($global:Fault -eq "stage" -and $Destination -like "*new-gentle-cc.exe") { throw "fixture stage" }
    if ($global:Fault -eq "snapshot" -and $Destination -like "*old-gentle-cc.exe") { throw "fixture snapshot" }
    Microsoft.PowerShell.Management\Copy-Item @PSBoundParameters
  }
  function global:Move-Item {
    [CmdletBinding()]
    param([string]$LiteralPath, [string]$Destination, [switch]$Force)
    if ($LiteralPath -like "*new-gentle-cc.exe" -and $global:Fault -in @("rename", "restore")) { throw "fixture rename" }
    if ($LiteralPath -like "*old-gentle-ai-cc.exe" -and $global:Fault -eq "restore") { throw "fixture restore" }
    Microsoft.PowerShell.Management\Move-Item @PSBoundParameters
  }
  foreach ($existing in @($true, $false)) {
    foreach ($faultKind in @("stage", "snapshot", "rename", "restore")) {
      if (-not $existing -and $faultKind -in @("snapshot", "restore")) { continue }
      $global:Fault = ""
      $fixture = Join-Path $root "fault-$existing-$faultKind"
      New-Item -ItemType Directory -Path $fixture | Out-Null
      Copy-Item -LiteralPath $source -Destination (Join-Path $fixture "install.ps1")
      Write-Release (Join-Path $fixture "dist") "v1" "local bytes"
      $env:GENTLE_CC_VERSION = "v1"
      $env:GENTLE_CC_DEST = Join-Path $fixture "dest"
      New-Item -ItemType Directory -Path $env:GENTLE_CC_DEST | Out-Null
      foreach ($name in @("gentle-ai-cc.exe", "gentle-cc.exe")) {
        if ($existing) { [IO.File]::WriteAllText((Join-Path $env:GENTLE_CC_DEST $name), "old-$name") }
      }
      [IO.File]::WriteAllText((Join-Path $env:GENTLE_CC_DEST "unrelated"), "unchanged")
      $before = Snapshot $env:GENTLE_CC_DEST
      $global:Fault = $faultKind
      $failure = $null
      $warnings = @()
      try {
        & (Join-Path $fixture "install.ps1") 3>&1 | ForEach-Object {
          if ($_ -is [Management.Automation.WarningRecord]) { $warnings += $_ }
        }
      } catch { $failure = $_.Exception.Message }
      $global:Fault = ""
      $expectedFailure = if ($faultKind -eq "restore") { "fixture rename" } else { "fixture $faultKind" }
      Assert ($failure -eq $expectedFailure) "fault-$existing-$faultKind exact failure: $failure"
      if ($faultKind -eq "restore") {
        $recovery = @(Get-ChildItem -LiteralPath $env:GENTLE_CC_DEST -Directory -Force)
        Assert ($recovery.Count -eq 1) "failed restore retains recovery directory"
        Assert (([IO.File]::ReadAllText((Join-Path $recovery[0].FullName "old-gentle-ai-cc.exe"))) -eq "old-gentle-ai-cc.exe") "retains old binary"
        Assert (($warnings -join "`n").Contains("manual recovery required")) "explicit manual recovery warning"
        Assert (([IO.File]::ReadAllText((Join-Path $env:GENTLE_CC_DEST "gentle-cc.exe"))) -eq "old-gentle-cc.exe") "unreplaced wrapper preserved"
      } else {
        Assert ((Snapshot $env:GENTLE_CC_DEST) -eq $before) "fault-$existing-$faultKind bytes/absence preserved"
        Assert (@(Get-ChildItem -LiteralPath $env:GENTLE_CC_DEST -Directory -Force).Count -eq 0) "publication staging cleaned"
      }
      Assert (([IO.File]::ReadAllText((Join-Path $env:GENTLE_CC_DEST "unrelated"))) -eq "unchanged") "unrelated preserved"
      Write-Host "PASS: publication-$existing-$faultKind"
    }
  }
  foreach ($destinationName in @("gentle-ai-cc.exe", "gentle-cc.exe")) {
  foreach ($kind in @("directory", "junction")) {
    $fixture = Join-Path $root "$destinationName-$kind"
    New-Item -ItemType Directory -Path $fixture | Out-Null
    Copy-Item -LiteralPath $source -Destination (Join-Path $fixture "install.ps1")
    $dist = Join-Path $fixture "dist"
    Write-Release $dist "v1" "local bytes"
    $before = Snapshot $dist
    $env:GENTLE_CC_VERSION = "v1"
    $env:GENTLE_CC_DEST = Join-Path $fixture "dest"
    New-Item -ItemType Directory -Path $env:GENTLE_CC_DEST | Out-Null
    $installed = Join-Path $env:GENTLE_CC_DEST $destinationName
    $target = Join-Path $fixture "target"
    if ($kind -eq "directory") {
      New-Item -ItemType Directory -Path $installed | Out-Null
      $target = $installed
    } else {
      New-Item -ItemType Directory -Path $target | Out-Null
      New-Item -ItemType Junction -Path $installed -Target $target | Out-Null
    }
    [IO.File]::WriteAllText((Join-Path $target "keep"), "unchanged")
    $attributes = (Get-Item -LiteralPath $installed -Force).Attributes
    $callsBefore = $global:DownloadDirs.Count
    $failure = $null
    try { & (Join-Path $fixture "install.ps1") } catch { $failure = $_.Exception.Message }
    Assert ($failure -eq "unsafe destination: $installed") "$kind exact rejection: $failure"
    Assert ((Get-Item -LiteralPath $installed -Force).Attributes -eq $attributes) "$kind destination preserved"
    Assert (([IO.File]::ReadAllText((Join-Path $target "keep"))) -eq "unchanged") "$kind sentinel preserved"
    Assert (@(Get-ChildItem -LiteralPath $target -Force).Count -eq 1) "$kind no nested copy"
    Assert ((Snapshot $dist) -eq $before) "$kind local dist preserved"
    Assert ($global:DownloadDirs.Count -eq $callsBefore) "$kind no download"
    Write-Host "PASS: unsafe $destinationName $kind"
  }
  }
  foreach ($kind in @("file", "junction")) {
    $fixture = Join-Path $root "unsafe-root-$kind"
    New-Item -ItemType Directory -Path $fixture | Out-Null
    Copy-Item -LiteralPath $source -Destination (Join-Path $fixture "install.ps1")
    Write-Release (Join-Path $fixture "dist") "v1" "local bytes"
    $env:GENTLE_CC_VERSION = "v1"
    $env:GENTLE_CC_DEST = Join-Path $fixture "dest"
    if ($kind -eq "file") { [IO.File]::WriteAllText($env:GENTLE_CC_DEST, "keep") }
    else {
      $target = Join-Path $fixture "target"
      New-Item -ItemType Directory -Path $target | Out-Null
      [IO.File]::WriteAllText((Join-Path $target "keep"), "unchanged")
      New-Item -ItemType Junction -Path $env:GENTLE_CC_DEST -Target $target | Out-Null
    }
    $attributes = (Get-Item -LiteralPath $env:GENTLE_CC_DEST -Force).Attributes
    $failure = $null
    try { & (Join-Path $fixture "install.ps1") } catch { $failure = $_.Exception.Message }
    Assert ($failure -eq "unsafe destination directory: $env:GENTLE_CC_DEST") "unsafe root $kind exact rejection: $failure"
    Assert ((Get-Item -LiteralPath $env:GENTLE_CC_DEST -Force).Attributes -eq $attributes) "root attributes preserved"
    if ($kind -eq "file") { Assert (([IO.File]::ReadAllText($env:GENTLE_CC_DEST)) -eq "keep") "root file preserved" }
    else {
      Assert (@(Get-ChildItem -LiteralPath $target -Force).Count -eq 1) "root target unchanged"
      Assert (([IO.File]::ReadAllText((Join-Path $target "keep"))) -eq "unchanged") "root target bytes"
    }
    Write-Host "PASS: unsafe destination root $kind"
  }
  Assert ($guidance.Contains("Native wrapper runtime requires neither Bash nor Python.")) "native runtime guidance"
  Assert ($guidance.Contains("Direct binary calls skip shared-state cleanup; official sync may fail.")) "cleanup warning"
  Assert ($guidance.Contains("Do not run direct binary writes concurrently with the wrapper or each other.")) "concurrency warning"
  Write-Host "PASS: native guidance and shared-state warnings"
} finally {
  foreach ($name in $envNames) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
  if (Test-Path Function:\gh) { Remove-Item Function:\gh }
  if (Test-Path Function:\Copy-Item) { Remove-Item Function:\Copy-Item }
  if (Test-Path Function:\Move-Item) { Remove-Item Function:\Move-Item }
  if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
