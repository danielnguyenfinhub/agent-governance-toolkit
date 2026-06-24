# Copyright (c) Microsoft Corporation. Licensed under the MIT License.
#
# install-claude-plugin.ps1 — install the agt-governance Claude Code plugin
# into your local Claude plugins directory and install its npm dependencies.
#
# This reproduces the manual flow:
#   npm install --prefix "$env:USERPROFILE\.claude\plugins\agt-governance"
# but also copies the plugin source from this repo into that directory first,
# so a single command gives you a ready-to-load plugin.
#
# Usage:
#   pwsh scripts/install-claude-plugin.ps1 [-Target <dir>]
#
#   -Target  Optional. Where to install the plugin.
#            Default: $env:CLAUDE_PLUGIN_DIR, else
#                     $env:USERPROFILE\.claude\plugins\agt-governance
#
# Examples:
#   pwsh scripts/install-claude-plugin.ps1
#   pwsh scripts/install-claude-plugin.ps1 -Target "$env:USERPROFILE\.claude\plugins\agt-governance"

[CmdletBinding()]
param(
    [string]$Target
)

$ErrorActionPreference = 'Stop'

# Resolve repo root from this script's location (scripts/ lives at the root).
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
$PluginSrc = Join-Path $RepoRoot 'agent-governance-claude-code'

if (-not $Target -or $Target -eq '') {
    if ($env:CLAUDE_PLUGIN_DIR) {
        $Target = $env:CLAUDE_PLUGIN_DIR
    } else {
        $Target = Join-Path $env:USERPROFILE '.claude\plugins\agt-governance'
    }
}

function Test-Command($name) {
    return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

if (-not (Test-Command 'node') -or -not (Test-Command 'npm')) {
    Write-Error 'node and npm are required (Node.js 18+). Install them first.'
}

if (-not (Test-Path (Join-Path $PluginSrc 'package.json'))) {
    Write-Error "Plugin source not found at $PluginSrc. Run this from a checkout of the agent-governance-toolkit repo."
}

Write-Host 'Installing agt-governance plugin'
Write-Host "  source: $PluginSrc"
Write-Host "  target: $Target"

New-Item -ItemType Directory -Force -Path $Target | Out-Null

# Copy the plugin source, excluding build/VCS artifacts.
$exclude = @('.git', 'node_modules')
Get-ChildItem -Path $PluginSrc -Force | Where-Object { $exclude -notcontains $_.Name } | ForEach-Object {
    Copy-Item -Path $_.FullName -Destination $Target -Recurse -Force
}

Write-Host 'Installing npm dependencies (including dev)...'
npm install --prefix "$Target" --no-audit --no-fund
if ($LASTEXITCODE -ne 0) {
    Write-Error "npm install failed with exit code $LASTEXITCODE"
}

Write-Host ''
Write-Host "Done. Plugin installed at: $Target"
Write-Host 'Load it with:'
Write-Host "  claude --plugin-dir `"$Target`""
