[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$sourceRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$testRoot = Join-Path $tempBase ("aitext-git-policy-" + [guid]::NewGuid().ToString("N"))

function Invoke-TestGit {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Repository,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [switch]$ExpectFailure
    )

    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $output = & git -C $Repository @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorAction
    $text = ($output | ForEach-Object { "$_" }) -join "`n"

    if ($ExpectFailure) {
        if ($exitCode -eq 0) {
            throw "Expected failure but command succeeded: git $($Arguments -join ' ')"
        }
        return $text
    }

    if ($exitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed:`n$text"
    }

    return $text
}

function Write-Utf8File {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Write-TestHandoff {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [string]$Note = "test task",
        [switch]$EmptySection
    )

    $status = if ($EmptySection) {
        ""
    } else {
        "| 最后更新时间 | 2026-10-04 |`n| 状态 | test fixture |"
    }

    $content = @"
# RM 交接总文档

## 1. 文档状态

$status

## 2. 一句话交接

Test fixture.

## 3. 当前目标与范围

Test fixture scope.

## 4. 权威文件

- RM_HANDOFF.md

## 5. 已锁定决定

- Test fixture decision.

## 6. 当前进度与验证

Test fixture progress.

## 7. 风险、阻塞与下一步

Test fixture next step.

## 8. 变更记录

### 2026-10-04 / $Note

Test fixture record.
"@

    Write-Utf8File -Path $Path -Content $content
}

function New-TestRepository {
    $repository = Join-Path $testRoot ([guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $repository -Force | Out-Null

    Copy-Item -LiteralPath (Join-Path $sourceRoot ".githooks") -Destination $repository -Recurse

    Invoke-TestGit -Repository $repository -Arguments @("init", "-b", "main") | Out-Null
    Invoke-TestGit -Repository $repository -Arguments @("config", "user.name", "Git Policy Test") | Out-Null
    Invoke-TestGit -Repository $repository -Arguments @("config", "user.email", "git-policy-test@example.invalid") | Out-Null
    Invoke-TestGit -Repository $repository -Arguments @("config", "core.autocrlf", "false") | Out-Null

    $hooksPath = (Join-Path $repository ".githooks").Replace("\", "/")
    Invoke-TestGit -Repository $repository -Arguments @("config", "core.hooksPath", $hooksPath) | Out-Null

    Write-Utf8File -Path (Join-Path $repository "base.txt") -Content "baseline`n"
    Write-TestHandoff -Path (Join-Path $repository "RM_HANDOFF.md") -Note "baseline"

    Invoke-TestGit -Repository $repository -Arguments @("add", "--all") | Out-Null
    Invoke-TestGit -Repository $repository -Arguments @(
        "update-index",
        "--chmod=+x",
        ".githooks/pre-commit",
        ".githooks/commit-msg",
        ".githooks/pre-push"
    ) | Out-Null
    Invoke-TestGit -Repository $repository -Arguments @("commit", "-m", "chore: 建立测试基线") | Out-Null

    return $repository
}

function Add-FormalChange {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Repository,
        [string]$HandoffNote = "formal change"
    )

    Write-Utf8File -Path (Join-Path $Repository "change.txt") -Content "formal change`n"
    Write-TestHandoff -Path (Join-Path $Repository "RM_HANDOFF.md") -Note $HandoffNote
}

function Assert-Clean {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Repository
    )

    $status = Invoke-TestGit -Repository $Repository -Arguments @("status", "--short")
    if ($status.Trim().Length -ne 0) {
        throw "Expected clean worktree, got:`n$status"
    }
}

if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot ".githooks") -PathType Container)) {
    throw "Cannot find .githooks under $sourceRoot"
}

New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

try {
    $repository = New-TestRepository
    Add-FormalChange -Repository $repository -HandoffNote "valid commit"
    Invoke-TestGit -Repository $repository -Arguments @("add", "--all") | Out-Null
    Invoke-TestGit -Repository $repository -Arguments @("commit", "-m", "docs: 验证合法提交") | Out-Null
    Assert-Clean -Repository $repository
    Write-Host "PASS valid atomic commit"

    $repository = New-TestRepository
    Add-FormalChange -Repository $repository -HandoffNote "invalid message"
    Invoke-TestGit -Repository $repository -Arguments @("add", "--all") | Out-Null
    Invoke-TestGit -Repository $repository -Arguments @("commit", "-m", "invalid message") -ExpectFailure | Out-Null
    Write-Host "PASS invalid commit subject is rejected"

    $repository = New-TestRepository
    Add-FormalChange -Repository $repository -HandoffNote "untracked file"
    Invoke-TestGit -Repository $repository -Arguments @("add", "--all") | Out-Null
    Write-Utf8File -Path (Join-Path $repository "untracked.txt") -Content "untracked`n"
    Invoke-TestGit -Repository $repository -Arguments @("commit", "-m", "docs: 验证未跟踪文件") -ExpectFailure | Out-Null
    Write-Host "PASS untracked file is rejected"

    $repository = New-TestRepository
    Add-FormalChange -Repository $repository -HandoffNote "secret fixture"
    $secretFixture = "sk-" + "testonly1234567890ABCDEF"
    Write-Utf8File -Path (Join-Path $repository "change.txt") -Content "token=$secretFixture`n"
    Invoke-TestGit -Repository $repository -Arguments @("add", "--all") | Out-Null
    Invoke-TestGit -Repository $repository -Arguments @("commit", "-m", "docs: 验证密钥模式") -ExpectFailure | Out-Null
    Write-Host "PASS high-confidence secret pattern is rejected"

    $repository = New-TestRepository
    Add-FormalChange -Repository $repository -HandoffNote "sensitive path"
    Write-Utf8File -Path (Join-Path $repository ".env") -Content "MODEL_API_KEY=placeholder`n"
    Invoke-TestGit -Repository $repository -Arguments @("add", "--all") | Out-Null
    Invoke-TestGit -Repository $repository -Arguments @("commit", "-m", "docs: 验证敏感路径") -ExpectFailure | Out-Null
    Write-Host "PASS sensitive credential path is rejected"

    $repository = New-TestRepository
    Add-FormalChange -Repository $repository -HandoffNote "unstaged file"
    Invoke-TestGit -Repository $repository -Arguments @("add", "--all") | Out-Null
    Write-Utf8File -Path (Join-Path $repository "change.txt") -Content "changed after staging`n"
    Invoke-TestGit -Repository $repository -Arguments @("commit", "-m", "docs: 验证未暂存修改") -ExpectFailure | Out-Null
    Write-Host "PASS unstaged tracked change is rejected"

    $repository = New-TestRepository
    Write-Utf8File -Path (Join-Path $repository "change.txt") -Content "missing handoff`n"
    Invoke-TestGit -Repository $repository -Arguments @("add", "change.txt") | Out-Null
    Invoke-TestGit -Repository $repository -Arguments @("commit", "-m", "docs: 验证缺少交接更新") -ExpectFailure | Out-Null
    Write-Host "PASS missing handoff update is rejected"

    $repository = New-TestRepository
    Write-Utf8File -Path (Join-Path $repository "change.txt") -Content "empty section`n"
    Write-TestHandoff -Path (Join-Path $repository "RM_HANDOFF.md") -Note "empty section" -EmptySection
    Invoke-TestGit -Repository $repository -Arguments @("add", "--all") | Out-Null
    Invoke-TestGit -Repository $repository -Arguments @("commit", "-m", "docs: 验证空交接章节") -ExpectFailure | Out-Null
    Write-Host "PASS empty handoff section is rejected"

    $repository = New-TestRepository
    $remote = Join-Path $testRoot ([guid]::NewGuid().ToString("N") + ".git")
    Invoke-TestGit -Repository $repository -Arguments @("init", "--bare", $remote) | Out-Null
    Invoke-TestGit -Repository $repository -Arguments @("remote", "add", "origin", $remote) | Out-Null
    Invoke-TestGit -Repository $repository -Arguments @("push", "-u", "origin", "main") | Out-Null
    Write-Utf8File -Path (Join-Path $repository "base.txt") -Content "dirty before push`n"
    Invoke-TestGit -Repository $repository -Arguments @("push") -ExpectFailure | Out-Null
    Write-Host "PASS dirty worktree blocks push"

    Write-Host "All Git policy tests passed."
}
finally {
    $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
    if (-not $resolvedTestRoot.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove test directory outside the temp root: $resolvedTestRoot"
    }

    if (Test-Path -LiteralPath $resolvedTestRoot) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}
