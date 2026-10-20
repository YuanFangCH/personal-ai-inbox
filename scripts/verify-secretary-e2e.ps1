<#
.SYNOPSIS
Runs the approved SEC-001–100 new-feature matrix on Android phone/tablet AVDs
and the native Windows desktop runner.
#>
param(
    [ValidateSet('all', 'phone', 'tablet', 'windows')]
    [string]$Platforms = 'all',
    [string[]]$CaseIds = @(),
    [string]$PhoneAvd = 'aitext_honor_phone',
    [string]$TabletAvd = 'aitext_galaxy_tab',
    [int]$PhonePort = 5560,
    [int]$TabletPort = 5562,
    [string]$ResultRoot = '.\test-results\secretary-100-final',
    [switch]$KeepRunning,
    [switch]$SkipVersionCheck
)

$ErrorActionPreference = 'Stop'
$CaseIds = @($CaseIds | ForEach-Object { $_ -split '[,;]' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if (Test-Path variable:PSNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $false
}
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$appRoot = Join-Path $repoRoot 'app'
$planPath = Join-Path $repoRoot 'docs\testing\secretary-100-case-plan.md'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$sha = (& git -C $repoRoot rev-parse HEAD).Trim()
$dirty = [bool](& git -C $repoRoot status --porcelain)
$runId = "$stamp-$($sha.Substring(0, 8))"
$resultBase = if ([IO.Path]::IsPathRooted($ResultRoot)) { $ResultRoot } else { Join-Path $repoRoot $ResultRoot }
$runRoot = Join-Path $resultBase $runId
$casesRoot = Join-Path $runRoot 'cases'
New-Item -ItemType Directory -Force -Path $casesRoot | Out-Null

function Resolve-Flutter {
    $command = Get-Command flutter -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $candidate = 'E:\DevTools\Flutter\bin\flutter.bat'
    if (Test-Path -LiteralPath $candidate) { return $candidate }
    throw 'Flutter executable was not found.'
}

function Resolve-AndroidSdk {
    foreach ($candidate in @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, 'E:\DevTools\Android\Sdk', (Join-Path $env:LOCALAPPDATA 'Android\Sdk'))) {
        if ($candidate -and (Test-Path -LiteralPath (Join-Path $candidate 'platform-tools\adb.exe'))) { return $candidate }
    }
    throw 'Android SDK was not found.'
}

function Start-Avd {
    param([string]$Name, [int]$Port)
    $device = "emulator-$Port"
    $existing = & $script:Adb devices | Select-String -Pattern "^$device\s+device$"
    if ($existing) { return @{ Device = $device; Started = $false } }
    $emulator = Join-Path $script:AndroidSdk 'emulator\emulator.exe'
    $process = Start-Process -FilePath $emulator -WindowStyle Hidden -PassThru -ArgumentList @(
        '-avd', $Name, '-port', "$Port", '-no-snapshot-save', '-no-boot-anim',
        '-no-audio', '-gpu', 'swiftshader_indirect'
    )
    $script:EmulatorProcesses[$device] = $process
    & $script:Adb -s $device wait-for-device | Out-Null
    $deadline = (Get-Date).AddMinutes(5)
    do {
        Start-Sleep -Seconds 2
        $booted = (& $script:Adb -s $device shell getprop sys.boot_completed 2>$null).Trim()
        if ($booted -eq '1') { break }
        if ((Get-Date) -gt $deadline) { throw "$device failed to boot within five minutes." }
    } while ($true)
    return @{ Device = $device; Started = $true }
}

function Stop-Avd {
    param([string]$Device)
    if (-not $script:EmulatorProcesses.ContainsKey($Device)) { return }
    & $script:Adb -s $Device emu kill 2>$null | Out-Null
    Start-Sleep -Seconds 3
    $process = $script:EmulatorProcesses[$Device]
    if (-not $process.HasExited) { $process.Kill() }
    $script:EmulatorProcesses.Remove($Device)
}

function Get-DeviceInfo {
    param([string]$Device)
    $sizeText = (& $script:Adb -s $Device shell wm size | Select-String 'Physical size').ToString()
    $densityText = (& $script:Adb -s $Device shell wm density | Select-String 'Physical density').ToString()
    $size = [regex]::Match($sizeText, '(\d+)x(\d+)')
    $density = [regex]::Match($densityText, '(\d+)')
    if (-not $size.Success -or -not $density.Success) { throw "Unable to measure display for $Device." }
    $logicalWidth = [math]::Round(([double]$size.Groups[1].Value * 160 / [double]$density.Groups[1].Value), 1)
    [pscustomobject]@{
        Device = $Device
        Android = (& $script:Adb -s $Device shell getprop ro.build.version.release).Trim()
        PhysicalSize = "$($size.Groups[1].Value)x$($size.Groups[2].Value)"
        Density = [int]$density.Groups[1].Value
        LogicalWidthDp = $logicalWidth
    }
}

function Invoke-Leg {
    param([string]$Name, [string]$TestFile, [string[]]$SelectedIds, [string[]]$ExtraArguments)
    $log = Join-Path $runRoot "$Name.log"
    $arguments = @('test', $TestFile) + $ExtraArguments + @('--reporter', 'expanded')
    Write-Host "=== $Name ($($SelectedIds.Count) cases) ==="
    Push-Location $appRoot
    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $script:Flutter @arguments 2>&1 | Tee-Object -FilePath $log
        $exit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
        Pop-Location
    }
    $logText = Get-Content -Raw -LiteralPath $log
    foreach ($caseId in $SelectedIds) {
        $passed = Select-String -Path $log -SimpleMatch "SEC_CASE_RESULT|$caseId|passed" -Quiet
        $failed = Select-String -Path $log -Pattern ([regex]::Escape($caseId) + '.*\[E\]') -Quiet
        $status = if ($passed) { 'passed' } elseif ($failed -or $exit -ne 0) { 'failed' } else { 'not_executed' }
        $metricMatch = [regex]::Match($logText, 'SEC_CASE_METRIC\|' + [regex]::Escape($caseId) + '\|(\{[^\r\n]*\})')
        $metrics = if ($metricMatch.Success) { $metricMatch.Groups[1].Value | ConvertFrom-Json } else { @{} }
        [pscustomobject]@{
            id = $caseId; platform = $Name; status = $status
            log = [IO.Path]::GetFileName($log); sha = $script:CommitSha
            started_at = $script:LegStart.ToString('o')
            metrics = $metrics
        } | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 (Join-Path $casesRoot "$caseId.json")
    }
    $script:Legs.Add([pscustomobject]@{ platform = $Name; exitCode = $exit; log = [IO.Path]::GetFileName($log); cases = $SelectedIds.Count })
}

$flutter = Resolve-Flutter
$script:Flutter = $flutter
$script:CommitSha = $sha
$localNugetDirectory = Join-Path $appRoot 'build\tooling'
if (Test-Path -LiteralPath (Join-Path $localNugetDirectory 'nuget.exe')) {
    $env:PATH = "$localNugetDirectory;$env:PATH"
}
$script:Legs = [System.Collections.Generic.List[object]]::new()
$script:EmulatorProcesses = @{}
$script:LegStart = Get-Date
if (-not $SkipVersionCheck) {
    . (Join-Path $PSScriptRoot 'assert-flutter-version.ps1') -FlutterExecutable $flutter
}

$caseRows = @{}
foreach ($line in Get-Content -LiteralPath $planPath) {
    if ($line -match '^\| (SEC-\d{3}) \| (phone|tablet|windows) \|') {
        $caseRows[$Matches[1]] = $Matches[2]
    }
}
if ($caseRows.Count -ne 100) { throw "The plan has $($caseRows.Count) parsed cases, expected 100." }
if ($CaseIds.Count -gt 0) {
    $unknown = @($CaseIds | Where-Object { -not $caseRows.ContainsKey($_) })
    if ($unknown.Count -gt 0) { throw "Unknown case IDs: $($unknown -join ', ')" }
    if (@($CaseIds | Select-Object -Unique).Count -ne $CaseIds.Count) { throw 'CaseIds contains duplicates.' }
}
$platformsToRun = if ($Platforms -eq 'all') { @('phone', 'tablet', 'windows') } else { @($Platforms) }
$selectedCandidate = if ($CaseIds.Count -gt 0) { $CaseIds } else { @($caseRows.Keys | Sort-Object) }
$selectedAll = @($selectedCandidate | Where-Object { $platformsToRun -contains $caseRows[$_] })
if ($CaseIds.Count -gt 0 -and $selectedAll.Count -ne $CaseIds.Count) {
    throw 'CaseIds includes IDs outside the selected platform set.'
}
$manifest = [ordered]@{
    runId = $runId; commit = $sha; workingTreeDirty = $dirty; startedAt = (Get-Date).ToString('o')
    flutter = (& $flutter --version | Select-Object -First 1); platforms = $platformsToRun
    cases = @($selectedAll); runtime = 'deterministic model/sync/voice fixture; real Flutter UI and SQLite; actual microphone, TTS and live cloud excluded'
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 (Join-Path $runRoot 'manifest.json')

$script:AndroidSdk = $null
$script:Adb = $null
if ($platformsToRun | Where-Object { $_ -in @('phone', 'tablet') }) {
    $script:AndroidSdk = Resolve-AndroidSdk
    $script:Adb = Join-Path $script:AndroidSdk 'platform-tools\adb.exe'
    $env:ANDROID_HOME = $script:AndroidSdk; $env:ANDROID_SDK_ROOT = $script:AndroidSdk
    $env:GRADLE_OPTS = '-Djavax.net.ssl.trustStoreType=WINDOWS-ROOT'
}

try {
    foreach ($platform in $platformsToRun) {
        $selected = @($selectedAll | Where-Object { $caseRows[$_] -eq $platform })
        if ($selected.Count -eq 0) { throw "No selected case belongs to $platform." }
        if ($platform -eq 'phone' -or $platform -eq 'tablet') {
            $avdName = if ($platform -eq 'phone') { $PhoneAvd } else { $TabletAvd }
            $port = if ($platform -eq 'phone') { $PhonePort } else { $TabletPort }
            $avd = Start-Avd -Name $avdName -Port $port
            $deviceInfo = Get-DeviceInfo -Device $avd.Device
            if ($platform -eq 'phone' -and $deviceInfo.LogicalWidthDp -ge 600) { throw "Phone AVD is $($deviceInfo.LogicalWidthDp)dp wide." }
            if ($platform -eq 'tablet' -and $deviceInfo.LogicalWidthDp -lt 600) { throw "Tablet AVD is only $($deviceInfo.LogicalWidthDp)dp wide." }
            $deviceInfo | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 (Join-Path $runRoot "$platform-device.json")
            $script:LegStart = Get-Date
            $extra = @('-d', $avd.Device, "--dart-define=E2E_PLATFORM=$platform")
            if ($CaseIds.Count -gt 0) { $extra += "--dart-define=E2E_CASE_IDS=$($selected -join ',')" }
            Invoke-Leg -Name $platform -TestFile 'integration_test/secretary_100_android_test.dart' -SelectedIds $selected -ExtraArguments $extra
            if (-not $KeepRunning) { Stop-Avd -Device $avd.Device }
        } else {
            $script:LegStart = Get-Date
            $extra = @('-d', 'windows')
            if ($CaseIds.Count -gt 0) { $extra += "--dart-define=E2E_CASE_IDS=$($selected -join ',')" }
            Invoke-Leg -Name $platform -TestFile 'integration_test/secretary_100_windows_test.dart' -SelectedIds $selected -ExtraArguments $extra
        }
    }
} finally {
    if (-not $KeepRunning) { foreach ($device in @($script:EmulatorProcesses.Keys)) { Stop-Avd -Device $device } }
}

$caseResults = @(Get-ChildItem -LiteralPath $casesRoot -Filter '*.json' | ForEach-Object { Get-Content -Raw $_.FullName | ConvertFrom-Json })
$summary = [ordered]@{
    runId = $runId; commit = $sha; workingTreeDirtyAtStart = $dirty
    counts = @{
        passed = @($caseResults | Where-Object status -eq 'passed').Count
        failed = @($caseResults | Where-Object status -eq 'failed').Count
        notExecuted = @($caseResults | Where-Object status -eq 'not_executed').Count
    }
    legs = @($script:Legs); cases = $caseResults
}
$summary | ConvertTo-Json -Depth 12 | Set-Content -Encoding utf8 (Join-Path $runRoot 'summary.json')
Write-Host "SEC results: $($summary.counts.passed) passed, $($summary.counts.failed) failed, $($summary.counts.notExecuted) not executed."
Write-Host "Evidence: $runRoot"
if ($summary.counts.passed -ne $selectedAll.Count -or $summary.counts.failed -gt 0 -or $summary.counts.notExecuted -gt 0) {
    throw 'The selected SEC matrix is incomplete or contains failures.'
}
