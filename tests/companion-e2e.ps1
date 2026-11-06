# Real release test: execute only on disposable GitHub-hosted runners.
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or -not $env:RUNNER_TEMP) {
  throw 'This test requires a disposable GitHub-hosted runner.'
}
$root = Join-Path $env:RUNNER_TEMP ('companion-e2e-' + [guid]::NewGuid().ToString('N'))
$homeDir = Join-Path $root 'home'
$binDir = Join-Path $root 'bin'
$tempDir = Join-Path $root 'tmp'
$workDir = Join-Path $root 'work'
foreach ($dir in @($homeDir, $binDir, $tempDir, $workDir)) {
  New-Item -ItemType Directory -Path $dir | Out-Null
}
$repo = Split-Path -Parent $PSScriptRoot
$env:HOME = $homeDir
$env:USERPROFILE = $homeDir
$env:LOCALAPPDATA = Join-Path $homeDir 'AppData/Local'
$env:APPDATA = Join-Path $homeDir 'AppData/Roaming'
$env:XDG_CONFIG_HOME = Join-Path $homeDir '.config'
$env:XDG_CACHE_HOME = Join-Path $homeDir '.cache'
$env:XDG_DATA_HOME = Join-Path $homeDir '.local/share'
$env:TMP = $tempDir
$env:TEMP = $tempDir
$env:TMPDIR = $tempDir
$env:GENTLE_CC_DEST = $binDir
$env:GENTLE_CC_VERSION = '4.3.1-cc.2'
$env:GENTLE_CC_REPO = Join-Path $root 'no-source-checkout'
Remove-Item Env:GENTLE_AI_HOME, Env:GENTLE_CC_SOURCE, Env:GENTLE_CC_REF, Env:GENTLE_CC_OWNER_REPO, Env:GH_TOKEN, Env:GITHUB_TOKEN -ErrorAction SilentlyContinue

function Assert-Exit($Description) {
  if ($LASTEXITCODE -ne 0) { throw "$Description failed with exit code $LASTEXITCODE" }
}
function Assert-Result($Phase) {
  $agentDir = Join-Path $homeDir '.commandcode'
  $agentsFile = Join-Path $agentDir 'AGENTS.md'
  $mcpFile = Join-Path $agentDir 'mcp.json'
  $stateFile = Join-Path $homeDir '.gentle-ai/state.json'
  if (-not (Test-Path -LiteralPath $agentsFile -PathType Leaf) -or (Get-Item -LiteralPath $agentsFile).Length -eq 0) {
    throw "$Phase`: missing or empty AGENTS.md"
  }
  if (-not (Test-Path -LiteralPath $mcpFile -PathType Leaf)) { throw "$Phase`: missing mcp.json" }
  $mcp = Get-Content -LiteralPath $mcpFile -Raw | ConvertFrom-Json -ErrorAction Stop
  foreach ($server in @('engram', 'context7')) {
    if (-not $mcp.mcpServers -or -not $mcp.mcpServers.PSObject.Properties[$server] -or
        -not $mcp.mcpServers.$server.command) { throw "$Phase`: missing MCP server command: $server" }
  }
  if ($IsLinux) {
    $engramEntry = $mcp.mcpServers.engram
    $engramArgs = @($engramEntry.args)
    if ($engramArgs.Count -ne 2 -or $engramArgs[0] -cne 'mcp' -or $engramArgs[1] -cne '--tools=agent') {
      throw "$Phase`: unexpected Engram MCP arguments"
    }
    $resolvedEngram = Get-Command -Name $engramEntry.command -CommandType Application -ErrorAction SilentlyContinue
    if (-not $resolvedEngram -or
        [System.IO.Path]::GetFullPath($resolvedEngram.Source) -cne [System.IO.Path]::GetFullPath($engramBinary)) {
      throw "$Phase`: Engram MCP command does not resolve to the checksum-verified test binary"
    }
  }
  $skillsDir = Join-Path $agentDir 'skills'
  if ($IsLinux) {
    $skillDir = Join-Path $skillsDir 'skill-creator'
    $skillFile = Join-Path $skillDir 'SKILL.md'
    $referenceDir = Join-Path $skillDir 'references'
    $styleGuideFile = Join-Path $referenceDir 'skill-style-guide.md'
    foreach ($path in @($skillsDir, $skillDir, $skillFile, $referenceDir, $styleGuideFile)) {
      if (-not (Test-Path -LiteralPath $path)) { throw "$Phase`: missing skill artifact: $path" }
      $item = Get-Item -LiteralPath $path
      if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "$Phase`: linked skill artifact is not accepted: $path"
      }
    }
    if ((Get-Item -LiteralPath $skillFile).PSIsContainer -or
        (Get-Item -LiteralPath $styleGuideFile).PSIsContainer -or
        (Get-Item -LiteralPath $skillFile).Length -eq 0 -or
        (Get-Item -LiteralPath $styleGuideFile).Length -eq 0) {
      throw "$Phase`: skill-creator or its style guide is empty or not a file"
    }
    $skillText = Get-Content -LiteralPath $skillFile -Raw
    $styleGuideText = Get-Content -LiteralPath $styleGuideFile -Raw
    if ($skillText -notmatch '(?m)^name:\s*skill-creator\s*$') {
      throw "$Phase`: skill-creator metadata is missing or invalid"
    }
    if ($styleGuideText -notmatch '(?m)^#\s+\S') {
      throw "$Phase`: skill-style-guide.md has no Markdown heading"
    }
  } elseif (-not (Test-Path -LiteralPath $skillsDir -PathType Container) -or
            -not (Get-ChildItem -LiteralPath $skillsDir -Filter 'SKILL.md' -File -Recurse | Select-Object -First 1)) {
    throw "$Phase`: no installed skill found"
  }
  if (-not (Test-Path -LiteralPath $stateFile -PathType Leaf)) { throw "$Phase`: missing state.json" }
  $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json -ErrorAction Stop
  if (@($state.installed_agents) | Where-Object { $_ -ceq 'command-code' -or $_ -ceq 'commandcode' }) {
    throw "$Phase`: companion agent leaked into shared state"
  }
  Write-Host "$Phase`: AGENTS.md, MCP JSON, skills and shared state checks passed"
}

Write-Host "Testing public release $env:GENTLE_CC_VERSION on $env:RUNNER_OS / $env:RUNNER_ARCH; network is not restricted."
Write-Host "Checkout: $env:GITHUB_SHA; no secrets are deliberately passed to the test."
if ($IsWindows) {
  # Copy only the installer: an absent dist forces its public HTTPS release path.
  $stage = Join-Path $root 'installer-stage'
  New-Item -ItemType Directory -Path $stage | Out-Null
  Copy-Item -LiteralPath (Join-Path $repo 'install.ps1') -Destination (Join-Path $stage 'install.ps1')
  # Hide gh so this E2E deterministically verifies the unauthenticated public route.
  $originalPath = $env:PATH
  try {
    $env:PATH = "$env:SystemRoot\System32;$env:SystemRoot"
    if (Test-Path -LiteralPath (Join-Path $stage 'dist')) { throw 'Windows public-install fixture unexpectedly has dist/' }
    if (Get-Command gh -ErrorAction SilentlyContinue) { throw 'gh must be unavailable to force the public HTTPS path' }
    & (Join-Path $stage 'install.ps1')
  } finally {
    $env:PATH = $originalPath
  }
  $suffix = '.exe'
} else {
  & bash (Join-Path $repo 'gentle-cc-install.sh') --from-release 'https://github.com/AngelCLA/gentle-ai-cc/releases/download/4.3.1-cc.2' --version $env:GENTLE_CC_VERSION
  Assert-Exit 'release installer'
  $suffix = ''
}
if ($IsLinux) {
  $engramVersion = '3.6.2'
  # GitHub release asset digest; do not accept an unpinned third-party executable.
  $engramSha256 = '3527b7e7e8692fd4aaaf576d331cded19155523cf8b02c2de38744cccb229e89'
  $engramArchive = Join-Path $tempDir "engram_${engramVersion}_linux_amd64.tar.gz"
  $engramUrl = "https://github.com/Gentleman-Programming/engram/releases/download/v$engramVersion/engram_${engramVersion}_linux_amd64.tar.gz"
  $null = Invoke-WebRequest -Uri $engramUrl -OutFile $engramArchive -UseBasicParsing
  $actualEngramHash = (Get-FileHash -LiteralPath $engramArchive -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actualEngramHash -cne $engramSha256) {
    throw "Engram $engramVersion archive checksum mismatch: $actualEngramHash"
  }
  $engramExtractDir = Join-Path $root 'engram-release'
  New-Item -ItemType Directory -Path $engramExtractDir | Out-Null
  & tar -xzf $engramArchive -C $engramExtractDir
  Assert-Exit 'Engram archive extraction'
  $engramFiles = @(Get-ChildItem -LiteralPath $engramExtractDir -Filter 'engram' -File -Recurse)
  if ($engramFiles.Count -ne 1) { throw 'Engram archive must contain exactly one `engram` binary' }
  $engramBinary = $engramFiles[0].FullName
  if (($engramFiles[0].Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'Refusing linked Engram binary from release archive'
  }
  & chmod +x $engramBinary
  Assert-Exit 'Engram executable permissions'
  $engramBinDirectory = $engramFiles[0].DirectoryName
  $env:PATH = "$engramBinDirectory$([System.IO.Path]::PathSeparator)$env:PATH"
  $env:ENGRAM_DATA_DIR = Join-Path $root 'engram-data'
  New-Item -ItemType Directory -Path $env:ENGRAM_DATA_DIR | Out-Null
  & $engramBinary version
  Assert-Exit 'Engram version'
}
$companionBin = Join-Path $binDir "gentle-ai-cc$suffix"
$wrapper = Join-Path $binDir "gentle-cc$suffix"
if ($IsWindows) {
  # Exercise the wrapper's normal sibling lookup on Windows.
  Remove-Item Env:GENTLE_CC_BIN -ErrorAction SilentlyContinue
} else {
  # Preserve the Linux smoke's explicit companion selection.
  $env:GENTLE_CC_BIN = $companionBin
}
foreach ($path in @($companionBin, $wrapper)) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing installed binary: $path" }
  Write-Host ("SHA256 {0}  {1}" -f (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash, (Split-Path -Leaf $path))
}
Push-Location $workDir
try {
  & $companionBin version
  Assert-Exit 'companion version'
  & $wrapper install --preset full-gentleman
  Assert-Exit 'wrapper install'
  Assert-Result 'install'
  & $wrapper sync
  Assert-Exit 'wrapper sync'
  Assert-Result 'sync'
  if ($IsLinux) {
    & python3 (Join-Path $repo 'tests/engram-mcp-smoke.py') $engramBinary
    Assert-Exit 'Engram MCP runtime smoke'
  }
} finally {
  Pop-Location
}
