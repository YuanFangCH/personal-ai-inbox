[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Repository,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $output = & git -C $Repository @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed:`n$($output -join "`n")"
    }

    return ($output -join "`n")
}

$repository = (Invoke-Git -Repository $PSScriptRoot -Arguments @(
    "rev-parse",
    "--show-toplevel"
)).Trim()

$hooksPath = (Join-Path $repository ".githooks").Replace("\", "/")
$requiredHooks = @("pre-commit", "commit-msg", "pre-push")

if (-not (Test-Path -LiteralPath $hooksPath -PathType Container)) {
    throw "Git hooks directory is missing: $hooksPath"
}

foreach ($hook in $requiredHooks) {
    $hookPath = Join-Path $hooksPath $hook
    if (-not (Test-Path -LiteralPath $hookPath -PathType Leaf)) {
        throw "Required Git hook is missing: $hookPath"
    }
}

Invoke-Git -Repository $repository -Arguments @(
    "config",
    "--local",
    "--replace-all",
    "core.hooksPath",
    $hooksPath
) | Out-Null

Invoke-Git -Repository $repository -Arguments @(
    "config",
    "--local",
    "--replace-all",
    "commit.template",
    ".gitmessage"
) | Out-Null

Write-Host "Git hooks enabled."
Write-Host "  core.hooksPath   = $hooksPath"
Write-Host "  commit.template  = .gitmessage"
