param(
    [string]$HonorAvd = 'aitext_honor_phone',
    [string]$GalaxyAvd = 'aitext_galaxy_tab',
    [string]$SystemImage = 'system-images;android-35;google_apis;x86_64',
    [int]$HonorPort = 5560,
    [int]$GalaxyPort = 5562,
    [switch]$SkipHost,
    [switch]$SkipBuild,
    [switch]$SkipUi,
    [switch]$SkipSystemProbes,
    [switch]$KeepRunning
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$appRoot = Join-Path $repoRoot 'app'
$acceptanceScript = Join-Path $PSScriptRoot 'verify-device-acceptance.ps1'

function Resolve-Flutter {
    $command = Get-Command flutter -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }
    $candidates = @(
        'E:\DevTools\Flutter\bin\flutter.bat',
        (Join-Path $env:USERPROFILE 'flutter\bin\flutter.bat'),
        (Join-Path $env:LOCALAPPDATA 'flutter\bin\flutter.bat')
    )
    if ($env:FLUTTER_ROOT) {
        $candidates = @(
            (Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat')
        ) + $candidates
    }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }
    throw 'flutter was not found. Add Flutter to PATH or set FLUTTER_ROOT.'
}

function Resolve-AndroidSdk {
    $candidates = @(
        $env:ANDROID_HOME,
        $env:ANDROID_SDK_ROOT,
        'E:\DevTools\Android\Sdk',
        (Join-Path $env:LOCALAPPDATA 'Android\Sdk'),
        (Join-Path $env:USERPROFILE 'Android\Sdk')
    ) | Where-Object { $_ }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }
    throw 'Android SDK was not found. Set ANDROID_HOME or ANDROID_SDK_ROOT.'
}

function Resolve-JavaHome {
    $candidates = @(
        $env:JAVA_HOME,
        (Join-Path $env:LOCALAPPDATA 'Programs\Android Studio\jbr'),
        'C:\Program Files\Android\Android Studio\jbr',
        (Join-Path $env:LOCALAPPDATA 'Programs\Android Studio\jre'),
        'C:\Program Files\Android\Android Studio\jre'
    ) | Where-Object { $_ }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $candidate 'bin\java.exe')) {
            return $candidate
        }
    }

    $javaRoots = @(
        'C:\Program Files\Java',
        (Join-Path $env:LOCALAPPDATA 'Programs\Java')
    )
    foreach ($root in $javaRoots) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }
        $installations = Get-ChildItem -LiteralPath $root -Directory |
            Sort-Object Name -Descending
        foreach ($installation in $installations) {
            if (Test-Path -LiteralPath (Join-Path $installation.FullName 'bin\java.exe')) {
                return $installation.FullName
            }
        }
    }
    return $null
}

function Invoke-OrThrow {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Label,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Command
    )
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE"
    }
}

function Get-VirtualSerial {
    param([int]$Port)
    return "emulator-$Port"
}

function Ensure-VirtualDevice {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AvdName,
        [Parameter(Mandatory = $true)]
        [string]$DeviceProfile
    )
    $emulator = Join-Path $script:AndroidSdk 'emulator\emulator.exe'
    $existing = & $emulator -list-avds
    if (($existing | Where-Object { $_.Trim() -eq $AvdName }).Count -gt 0) {
        return
    }

    $systemImagePath = Join-Path $script:AndroidSdk (
        $SystemImage.Replace(';', '\')
    )
    if (-not (Test-Path -LiteralPath (Join-Path $systemImagePath 'package.xml'))) {
        throw "System image is missing: $SystemImage"
    }
    $avdManager = Join-Path $script:AndroidSdk 'cmdline-tools\latest\bin\avdmanager.bat'
    if (-not (Test-Path -LiteralPath $avdManager)) {
        throw "avdmanager was not found at $avdManager"
    }
    Write-Host "Creating $AvdName from $DeviceProfile"
    'no' | & $avdManager create avd `
        -n $AvdName `
        -k $SystemImage `
        -d $DeviceProfile `
        --force | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Could not create AVD $AvdName"
    }
}

function Get-AdbDeviceState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Serial
    )
    $output = & $script:Adb devices
    $line = $output |
        Where-Object { $_ -match "^$([regex]::Escape($Serial))\s+" } |
        Select-Object -First 1
    if (-not $line) {
        return $null
    }
    return ($line -split '\s+')[1]
}

function Get-RunningAvdName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Serial
    )
    if ((Get-AdbDeviceState -Serial $Serial) -ne 'device') {
        return $null
    }
    $nameOutput = & $script:Adb -s $Serial emu avd name 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $null
    }
    return (
        $nameOutput |
            Where-Object { $_ -match '\S' -and $_ -notmatch '^OK$' } |
            Select-Object -First 1
    ).Trim()
}

function Start-VirtualDevice {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AvdName,
        [Parameter(Mandatory = $true)]
        [int]$Port
    )
    $serial = Get-VirtualSerial -Port $Port
    $runningAvd = Get-RunningAvdName -Serial $serial
    if ($runningAvd) {
        if ($runningAvd -ne $AvdName) {
            throw "$serial is already running $runningAvd, not $AvdName."
        }
        Write-Host "Reusing $AvdName on $serial"
        return @{
            Serial = $serial
            Started = $false
        }
    }

    $emulator = Join-Path $script:AndroidSdk 'emulator\emulator.exe'
    if (-not (Test-Path -LiteralPath $emulator)) {
        throw "Android emulator was not found at $emulator"
    }
    $arguments = @(
        '-avd', $AvdName,
        '-port', "$Port",
        '-no-window',
        '-no-audio',
        '-no-boot-anim',
        '-no-snapshot-save'
    )
    Start-Process -FilePath $emulator `
        -ArgumentList $arguments `
        -WindowStyle Hidden | Out-Null
    Write-Host "Starting $AvdName on $serial"

    $connected = $false
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        if ((Get-AdbDeviceState -Serial $serial) -eq 'device') {
            $connected = $true
            break
        }
        Start-Sleep -Seconds 2
    }
    if (-not $connected) {
        throw "Could not connect to $serial within 120 seconds"
    }
    for ($attempt = 0; $attempt -lt 90; $attempt++) {
        $ready = (& $script:Adb -s $serial shell getprop sys.boot_completed 2>$null).Trim()
        if ($ready -eq '1') {
            break
        }
        Start-Sleep -Seconds 2
    }
    if ($ready -ne '1') {
        throw "$AvdName did not finish booting within 180 seconds"
    }
    & $script:Adb -s $serial shell input keyevent 82 | Out-Null
    return @{
        Serial = $serial
        Started = $true
    }
}

function Stop-VirtualDevice {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Serial,
        [Parameter(Mandatory = $true)]
        [bool]$Started
    )
    if ($KeepRunning -or -not $Started) {
        return
    }
    & $script:Adb -s $Serial emu kill 2>$null | Out-Null
    Write-Host "Stopped $Serial"
}

function Invoke-VirtualProfile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Profile,
        [Parameter(Mandatory = $true)]
        [string]$Serial
    )
    if (-not $SkipUi) {
        Invoke-OrThrow -Label "$Profile virtual UI matrix" -Command {
            & $script:Flutter test integration_test/device_acceptance_physical_test.dart `
                -d $Serial `
                --dart-define=DEVICE_UNDER_TEST=$Profile `
                --reporter expanded
        }
    }

    if (-not $SkipSystemProbes) {
        if ($Profile -eq 'honor-phone') {
            & $acceptanceScript `
                -SystemProbesOnly `
                -AllowUnverifiedDevice `
                -SkipReleaseBuild `
                -HonorSerial $Serial
        } else {
            & $acceptanceScript `
                -SystemProbesOnly `
                -AllowUnverifiedDevice `
                -SkipReleaseBuild `
                -GalaxySerial $Serial
        }
    }
}

$script:Flutter = Resolve-Flutter
$script:AndroidSdk = Resolve-AndroidSdk
$script:Adb = Join-Path $script:AndroidSdk 'platform-tools\adb.exe'
if (-not (Test-Path -LiteralPath $script:Adb)) {
    throw "adb was not found at $script:Adb"
}
$env:ANDROID_HOME = $script:AndroidSdk
$javaHome = Resolve-JavaHome
if ($javaHome) {
    $env:JAVA_HOME = $javaHome
}
$env:GRADLE_OPTS = '-Djavax.net.ssl.trustStoreType=WINDOWS-ROOT'

Push-Location $appRoot
try {
    if (-not $SkipHost) {
        Invoke-OrThrow -Label '100-case host acceptance matrix' -Command {
            & $script:Flutter test test/device_acceptance_100_cases_test.dart `
                --reporter expanded
        }
    }

    if (-not $SkipSystemProbes -and -not $SkipBuild) {
        Invoke-OrThrow -Label 'Android release APK build' -Command {
            & $script:Flutter build apk --release | Out-Host
        }
    }

    Ensure-VirtualDevice -AvdName $HonorAvd -DeviceProfile 'pixel_6'
    Ensure-VirtualDevice -AvdName $GalaxyAvd -DeviceProfile 'medium_tablet'

    $honor = Start-VirtualDevice -AvdName $HonorAvd -Port $HonorPort
    try {
        Invoke-VirtualProfile -Profile 'honor-phone' -Serial $honor.Serial
    }
    finally {
        Stop-VirtualDevice -Serial $honor.Serial -Started $honor.Started
    }

    $galaxy = Start-VirtualDevice -AvdName $GalaxyAvd -Port $GalaxyPort
    try {
        Invoke-VirtualProfile -Profile 'galaxy-tab' -Serial $galaxy.Serial
    }
    finally {
        Stop-VirtualDevice -Serial $galaxy.Serial -Started $galaxy.Started
    }
}
finally {
    Pop-Location
}

Write-Output 'Virtual device acceptance verification passed.'
