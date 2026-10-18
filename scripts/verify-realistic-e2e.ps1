<#
.SYNOPSIS
Runs the 100-scenario realistic end-to-end matrix on the Android AVDs and the
Windows desktop renderer.

.DESCRIPTION
Legs:
  phone   -> Android AVD (50 scenarios)
  tablet  -> Android AVD (25 scenarios)
  windows -> native Windows desktop runner (25 scenarios)

Each leg writes its own log under app/build/realistic-e2e/<timestamp>/.

.PARAMETER Platforms
all (default), android, phone, tablet or windows.

.PARAMETER KeepRunning
Leaves the Android emulators running after the leg.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\scripts\verify-realistic-e2e.ps1
#>
param(
    [ValidateSet('all', 'android', 'phone', 'tablet', 'windows')]
    [string]$Platforms = 'all',
    [string]$PhoneAvd = 'aitext_honor_phone',
    [string]$TabletAvd = 'aitext_galaxy_tab',
    [int]$PhonePort = 5560,
    [int]$TabletPort = 5562,
    [switch]$KeepRunning,
    [switch]$SkipVersionCheck
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$appRoot = Join-Path $repoRoot 'app'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logRoot = Join-Path $appRoot "build\realistic-e2e\$timestamp"

function Resolve-Flutter {
    $command = Get-Command flutter -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $candidates = @(
        'E:\DevTools\Flutter\bin\flutter.bat',
        (Join-Path $env:USERPROFILE 'flutter\bin\flutter.bat'),
        (Join-Path $env:LOCALAPPDATA 'flutter\bin\flutter.bat')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    throw 'flutter was not found. Add Flutter to PATH or install it at E:\DevTools\Flutter.'
}

function Resolve-AndroidSdk {
    $candidates = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT,
        'E:\DevTools\Android\Sdk',
        (Join-Path $env:LOCALAPPDATA 'Android\Sdk'))
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath (Join-Path $candidate 'platform-tools\adb.exe'))) {
            return $candidate
        }
    }
    throw 'Android SDK was not found. Set ANDROID_HOME.'
}

function Start-Emulator {
    param([string]$Name, [int]$Port)
    $emulator = Join-Path $script:AndroidSdk 'emulator\emulator.exe'
    if (-not (Test-Path -LiteralPath $emulator)) { throw "emulator.exe not found at $emulator" }
    $device = "emulator-$Port"
    $existing = & $script:Adb devices | Select-String -Pattern "^$device\s+device$"
    if ($existing) { return $device }
    Write-Host "Starting AVD $Name on $device ..."
    $arguments = @(
        '-avd', $Name,
        '-port', "$Port",
        '-no-snapshot-save',
        '-no-boot-anim',
        '-no-audio',
        '-gpu', 'swiftshader_indirect'
    )
    $process = Start-Process -FilePath $emulator -ArgumentList $arguments -PassThru
    $script:EmulatorProcesses[$device] = $process
    & $script:Adb -s $device wait-for-device | Out-Null
    $deadline = (Get-Date).AddMinutes(4)
    do {
        Start-Sleep -Seconds 3
        $booted = (& $script:Adb -s $device shell getprop sys.boot_completed 2>$null).Trim()
        if ($booted -eq '1') { break }
        if ((Get-Date) -gt $deadline) { throw "$device did not boot within 4 minutes." }
    } while ($true)
    Start-Sleep -Seconds 3
    Write-Host "$device booted."
    return $device
}

function Stop-Emulator {
    param([string]$Device)
    if (-not $script:EmulatorProcesses.ContainsKey($Device)) { return }
    & $script:Adb -s $Device emu kill 2>$null | Out-Null
    Start-Sleep -Seconds 4
    $process = $script:EmulatorProcesses[$Device]
    if (-not $process.HasExited) {
        $process.Kill()
    }
    $script:EmulatorProcesses.Remove($Device)
}

function Invoke-Leg {
    param(
        [string]$Name,
        [string]$TestFile,
        [string[]]$ExtraArguments
    )
    $log = Join-Path $logRoot "$Name.log"
    Write-Host "=== $Name ==="
    $started = Get-Date
    Push-Location $appRoot
    try {
        & $script:Flutter test $TestFile @ExtraArguments --reporter expanded 2>&1 |
            Tee-Object -FilePath $log
        $exit = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }
    $elapsed = [math]::Round(((Get-Date) - $started).TotalMinutes, 1)
    $passed = Select-String -Path $log -Pattern 'All tests passed!' -Quiet
    $script:Results.Add([pscustomobject]@{
            Leg      = $Name
            Exit     = $exit
            Passed   = [bool]$passed
            Minutes  = $elapsed
            Log      = $log
        })
    if ($exit -ne 0) {
        Write-Warning "Leg $Name failed (exit $exit). See $log"
    }
}

New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$script:Flutter = Resolve-Flutter
$script:AndroidSdk = $null
$script:Adb = $null
$script:EmulatorProcesses = @{}
$script:Results = [System.Collections.Generic.List[object]]::new()

if (-not $SkipVersionCheck) {
    . (Join-Path $PSScriptRoot 'assert-flutter-version.ps1') -FlutterExecutable $script:Flutter
}

$runAndroid = $Platforms -in @('all', 'android', 'phone', 'tablet')
$runWindows = $Platforms -in @('all', 'windows')

if ($runAndroid) {
    $script:AndroidSdk = Resolve-AndroidSdk
    $script:Adb = Join-Path $script:AndroidSdk 'platform-tools\adb.exe'
    $env:ANDROID_HOME = $script:AndroidSdk
    $env:ANDROID_SDK_ROOT = $script:AndroidSdk
    if (-not $env:JAVA_HOME) {
        $jdk = 'C:\Program Files\Java\jdk-17.0.2'
        if (Test-Path -LiteralPath $jdk) { $env:JAVA_HOME = $jdk }
    }
    $env:GRADLE_OPTS = '-Djavax.net.ssl.trustStoreType=WINDOWS-ROOT'
}

$failures = 0
try {
    if ($Platforms -in @('all', 'android', 'phone')) {
        $device = Start-Emulator -Name $PhoneAvd -Port $PhonePort
        try {
            Invoke-Leg -Name 'phone' `
                -TestFile 'integration_test/realistic_100_android_test.dart' `
                -ExtraArguments @('-d', $device, '--dart-define=E2E_PLATFORM=phone')
        }
        finally {
            if (-not $KeepRunning) { Stop-Emulator -Device $device }
        }
    }

    if ($Platforms -in @('all', 'android', 'tablet')) {
        $device = Start-Emulator -Name $TabletAvd -Port $TabletPort
        try {
            Invoke-Leg -Name 'tablet' `
                -TestFile 'integration_test/realistic_100_android_test.dart' `
                -ExtraArguments @('-d', $device, '--dart-define=E2E_PLATFORM=tablet')
        }
        finally {
            if (-not $KeepRunning) { Stop-Emulator -Device $device }
        }
    }

    if ($runWindows) {
        Invoke-Leg -Name 'windows' `
            -TestFile 'integration_test/realistic_100_windows_test.dart' `
            -ExtraArguments @('-d', 'windows')
    }
}
finally {
    if (-not $KeepRunning) {
        foreach ($device in @($script:EmulatorProcesses.Keys)) {
            Stop-Emulator -Device $device
        }
    }
}

Write-Host ''
Write-Host 'Realistic end-to-end summary'
$script:Results | Format-Table -AutoSize | Out-String | Write-Host
Write-Host "Logs: $logRoot"

foreach ($result in $script:Results) {
    if ($result.Exit -ne 0) { $failures++ }
}
if ($failures -gt 0) {
    throw "$failures leg(s) failed. Inspect the logs above."
}
Write-Host 'All realistic end-to-end legs passed.'
