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
  $skillsDir = Join-Path $agentDir 'skills'
  if (-not (Test-Path -LiteralPath $skillsDir -PathType Container) -or
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
  # Fetch the exact public assets into a new staging directory. The copied
  # installer then verifies both against the downloaded checksum manifest.
  $stage = Join-Path $root 'release-stage'
  $dist = Join-Path $stage 'dist'
  New-Item -ItemType Directory -Path $dist -Force | Out-Null
  Copy-Item -LiteralPath (Join-Path $repo 'install.ps1') -Destination (Join-Path $stage 'install.ps1')
  $base = 'https://github.com/AngelCLA/gentle-ai-cc/releases/download/4.3.1-cc.2'
  foreach ($name in @('checksums.txt', 'gentle-ai-cc_4.3.1-cc.2_windows_amd64.exe', 'gentle-cc_4.3.1-cc.2_windows_amd64.exe')) {
    Invoke-WebRequest -Uri "$base/$name" -OutFile (Join-Path $dist $name) -UseBasicParsing
  }
  & (Join-Path $stage 'install.ps1')
  $suffix = '.exe'
} else {
  & bash (Join-Path $repo 'gentle-cc-install.sh') --from-release 'https://github.com/AngelCLA/gentle-ai-cc/releases/download/4.3.1-cc.2' --version $env:GENTLE_CC_VERSION
  Assert-Exit 'release installer'
  $suffix = ''
}
$env:GENTLE_CC_BIN = Join-Path $binDir "gentle-ai-cc$suffix"
$wrapper = Join-Path $binDir "gentle-cc$suffix"
foreach ($path in @($env:GENTLE_CC_BIN, $wrapper)) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing installed binary: $path" }
  Write-Host ("SHA256 {0}  {1}" -f (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash, (Split-Path -Leaf $path))
}
Push-Location $workDir
try {
  & $env:GENTLE_CC_BIN version
  Assert-Exit 'companion version'
  & $wrapper install --preset full-gentleman
  Assert-Exit 'wrapper install'
  Assert-Result 'install'
  & $wrapper sync
  Assert-Exit 'wrapper sync'
  Assert-Result 'sync'
} finally {
  Pop-Location
}
