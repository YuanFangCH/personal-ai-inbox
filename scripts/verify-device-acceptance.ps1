param(
    [string]$HonorSerial,
    [string]$GalaxySerial,
    [string]$ReleaseApk,
    [switch]$SkipHost,
    [switch]$SkipPhysical,
    [switch]$SkipSystemProbes,
    [switch]$SkipReleaseBuild,
    [switch]$SystemProbesOnly,
    [switch]$AllowUnverifiedDevice
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$appRoot = Join-Path $repoRoot 'app'
$packageName = 'com.yuanfang.aitext.personal_ai_inbox'
$componentName = "$packageName/.MainActivity"
$evidenceRoot = Join-Path $appRoot 'build\device-acceptance'

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

function Resolve-Adb {
    $command = Get-Command adb -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $sdkCandidates = @(
        $env:ANDROID_HOME,
        $env:ANDROID_SDK_ROOT,
        'E:\DevTools\Android\Sdk',
        (Join-Path $env:LOCALAPPDATA 'Android\Sdk'),
        (Join-Path $env:USERPROFILE 'Android\Sdk')
    ) | Where-Object { $_ }
    foreach ($sdk in $sdkCandidates) {
        $candidate = Join-Path $sdk 'platform-tools\adb.exe'
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }
    throw 'adb was not found. Set ANDROID_HOME or ANDROID_SDK_ROOT.'
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
    return $null
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

function Read-DeviceProperty {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Serial,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )
    $value = & $script:Adb -s $Serial shell getprop $Name
    if ($LASTEXITCODE -ne 0) {
        throw "Could not read $Name from device $Serial"
    }
    return ($value | Out-String).Trim()
}

function Assert-DeviceProfile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfileName,
        [Parameter(Mandatory = $true)]
        [string]$Serial
    )

    $manufacturer = (Read-DeviceProperty $Serial 'ro.product.manufacturer').ToLowerInvariant()
    $model = Read-DeviceProperty $Serial 'ro.product.model'
    $release = Read-DeviceProperty $Serial 'ro.build.version.release'
    $sizeOutput = & $script:Adb -s $Serial shell wm size
    $densityOutput = & $script:Adb -s $Serial shell wm density
    $sizeMatch = [regex]::Match(($sizeOutput | Out-String), '(\d+)x(\d+)')
    $densityMatch = [regex]::Match(($densityOutput | Out-String), '(\d+)')
    if (-not $sizeMatch.Success -or -not $densityMatch.Success) {
        throw "Could not determine screen size or density for $Serial"
    }
    $pixelWidth = [int]$sizeMatch.Groups[1].Value
    $physicalHeight = [int]$sizeMatch.Groups[2].Value
    $density = [int]$densityMatch.Groups[1].Value
    $logicalWidth = [math]::Round($pixelWidth * 160.0 / $density, 1)

    if ($AllowUnverifiedDevice) {
        Write-Warning (
            "Device gate bypassed for development probe: {0} {1}, Android {2}, {3}px x {4}px, {5}dpi, {6}dp wide" -f
            $manufacturer, $model, $release, $pixelWidth, $physicalHeight, $density, $logicalWidth
        )
        return
    }

    switch ($ProfileName) {
        'honor-phone' {
            if ($manufacturer -ne 'honor') {
                throw "honor-phone requires manufacturer HONOR; got $manufacturer on $Serial"
            }
            if ($logicalWidth -ge 600) {
                throw "honor-phone requires a compact viewport below 600dp; got ${logicalWidth}dp"
            }
        }
        'galaxy-tab' {
            if ($manufacturer -ne 'samsung') {
                throw "galaxy-tab requires manufacturer samsung; got $manufacturer on $Serial"
            }
            if ($model -notmatch '^SM-T73') {
                throw "galaxy-tab requires Galaxy Tab S7 FE model SM-T73*; got $model"
            }
            if ($logicalWidth -lt 600) {
                throw "galaxy-tab requires an expanded viewport of at least 600dp; got ${logicalWidth}dp"
            }
        }
        default {
            throw "Unsupported device profile: $ProfileName"
        }
    }

    Write-Output (
        "Verified ${ProfileName} on ${Serial}: {0} {1}, Android {2}, {3}px x {4}px, {5}dpi, {6}dp wide" -f
        $manufacturer, $model, $release, $pixelWidth, $physicalHeight, $density, $logicalWidth
    )
}

function Resolve-ReleaseApk {
    if ($ReleaseApk) {
        $resolved = Resolve-Path -LiteralPath $ReleaseApk -ErrorAction Stop
        return $resolved.Path
    }

    $defaultApk = Join-Path $appRoot 'build\app\outputs\flutter-apk\app-release.apk'
    if ($SkipReleaseBuild) {
        if (-not (Test-Path -LiteralPath $defaultApk)) {
            throw 'Release APK is missing; omit -SkipReleaseBuild or pass -ReleaseApk.'
        }
        return $defaultApk
    }

    Invoke-OrThrow -Label 'Android release APK build' -Command {
        & $script:Flutter build apk --release | Out-Host
    }
    if (-not (Test-Path -LiteralPath $defaultApk)) {
        throw "Release APK was not produced at $defaultApk"
    }
    return $defaultApk
}

function Get-UiHierarchy {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Serial
    )
    $remotePath = '/sdcard/ai_inbox_device_probe.xml'
    & $script:Adb -s $Serial shell uiautomator dump $remotePath 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        return ''
    }
    return (& $script:Adb -s $Serial shell cat $remotePath | Out-String)
}

function Wait-ForUiText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Serial,
        [Parameter(Mandatory = $true)]
        [string]$Text,
        [int]$Attempts = 15
    )
    for ($attempt = 0; $attempt -lt $Attempts; $attempt++) {
        $xml = Get-UiHierarchy -Serial $Serial
        if ($xml -match [regex]::Escape($Text)) {
            return $xml
        }
        Start-Sleep -Seconds 1
    }
    throw "Timed out waiting for '$Text' on $Serial"
}

function Wait-ForUiNodeEnabled {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Serial,
        [Parameter(Mandatory = $true)]
        [string]$ResourceId,
        [int]$Attempts = 15
    )
    for ($attempt = 0; $attempt -lt $Attempts; $attempt++) {
        $xml = Get-UiHierarchy -Serial $Serial
        $pattern = '<node[^>]*resource-id="' + [regex]::Escape($ResourceId) + '"[^>]*>'
        $match = [regex]::Match($xml, $pattern)
        if ($match.Success -and $match.Value -match 'enabled="true"') {
            return $xml
        }
        Start-Sleep -Seconds 1
    }
    throw "Timed out waiting for enabled '$ResourceId' on $Serial"
}

function Wake-Device {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Serial
    )
    & $script:Adb -s $Serial shell input keyevent 224 | Out-Null
    & $script:Adb -s $Serial shell wm dismiss-keyguard | Out-Null
}

function Open-RestoredConversation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Serial,
        [Parameter(Mandatory = $true)]
        [string]$Marker
    )
    $inboxLabel = "$([char]0x6536)$([char]0x4EF6)$([char]0x7BB1)"
    for ($attempt = 0; $attempt -lt 15; $attempt++) {
        Wake-Device -Serial $Serial
        $xml = Get-UiHierarchy -Serial $Serial
        if ($xml -match [regex]::Escape($Marker)) {
            return $xml
        }

        if ($xml -match 'content-desc="Back"') {
            & $script:Adb -s $Serial shell input keyevent 4 | Out-Null
            Start-Sleep -Seconds 1
            continue
        }

        $pattern = '<node[^>]*content-desc="' +
            [regex]::Escape($inboxLabel) +
            '[^"]*"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"'
        $match = [regex]::Match($xml, $pattern)
        if ($match.Success) {
            $x = [int](
                ([int]$match.Groups[1].Value + [int]$match.Groups[3].Value) / 2
            )
            $y = [int](
                ([int]$match.Groups[2].Value + [int]$match.Groups[4].Value) / 2
            )
            & $script:Adb -s $Serial shell input tap $x $y | Out-Null
        }
        Start-Sleep -Seconds 1
    }
    throw "Could not restore '$Marker' through the inbox on $Serial"
}

function Save-DeviceScreenshot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Serial,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $remotePath = '/sdcard/ai_inbox_device_probe.png'
    & $script:Adb -s $Serial shell screencap -p $remotePath | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Could not capture screenshot on $Serial"
    }
    & $script:Adb -s $Serial pull $remotePath $Path | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Could not pull screenshot from $Serial"
    }
}

function Assert-IntentResolver {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Serial,
        [Parameter(Mandatory = $true)]
        [string]$Action
    )
    $output = & $script:Adb -s $Serial shell cmd package query-activities `
        --brief -a $Action -t text/plain
    if ($LASTEXITCODE -ne 0 -or ($output | Out-String) -notmatch [regex]::Escape($packageName)) {
        throw "$packageName does not resolve $Action text/plain on $Serial"
    }
}

function Get-UiNodeCenter {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Xml,
        [Parameter(Mandatory = $true)]
        [string]$Text
    )
    $pattern = '<node[^>]*text="' + [regex]::Escape($Text) +
        '"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"'
    $match = [regex]::Match($Xml, $pattern)
    if (-not $match.Success) {
        throw "Could not find tappable UI node '$Text'"
    }
    return @{
        X = [int](
            ([int]$match.Groups[1].Value + [int]$match.Groups[3].Value) / 2
        )
        Y = [int](
            ([int]$match.Groups[2].Value + [int]$match.Groups[4].Value) / 2
        )
    }
}

function Get-UiNodeCenterContaining {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Xml,
        [Parameter(Mandatory = $true)]
        [string]$Text
    )
    $pattern = '<node[^>]*text="[^"]*' + [regex]::Escape($Text) +
        '[^"]*"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"'
    $match = [regex]::Match($Xml, $pattern)
    if (-not $match.Success) {
        throw "Could not find tappable UI node containing '$Text'"
    }
    return @{
        X = [int](
            ([int]$match.Groups[1].Value + [int]$match.Groups[3].Value) / 2
        )
        Y = [int](
            ([int]$match.Groups[2].Value + [int]$match.Groups[4].Value) / 2
        )
    }
}

function Get-UiNodeCenterByResourceId {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Xml,
        [Parameter(Mandatory = $true)]
        [string]$ResourceId
    )
    $pattern = '<node[^>]*resource-id="' + [regex]::Escape($ResourceId) +
        '"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"'
    $match = [regex]::Match($Xml, $pattern)
    if (-not $match.Success) {
        throw "Could not find tappable resource '$ResourceId'"
    }
    return @{
        X = [int](
            ([int]$match.Groups[1].Value + [int]$match.Groups[3].Value) / 2
        )
        Y = [int](
            ([int]$match.Groups[2].Value + [int]$match.Groups[4].Value) / 2
        )
    }
}

function Invoke-ChooserProbe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfileName,
        [Parameter(Mandatory = $true)]
        [string]$Serial,
        [Parameter(Mandatory = $true)]
        [string]$ProfileCode,
        [Parameter(Mandatory = $true)]
        [string]$Timestamp
    )
    $marker = "AI_${ProfileCode}_C_$Timestamp"
    $appLabel = "$([char]0x4E2A)$([char]0x4EBA) AI $([char]0x6536)$([char]0x4EF6)$([char]0x7BB1)"
    $probeDirectory = Join-Path $evidenceRoot "$ProfileName\system_chooser"
    New-Item -ItemType Directory -Path $probeDirectory -Force | Out-Null

    Wake-Device -Serial $Serial
    & $script:Adb -s $Serial shell am force-stop $packageName
    Invoke-OrThrow -Label "$ProfileName system chooser launch" -Command {
        & $script:Adb -s $Serial shell am start -W `
            -a android.intent.action.SEND `
            -t text/plain `
            --es android.intent.extra.TEXT $marker
    }
    $moreLabel = "$([char]0x66F4)$([char]0x591A)"
    $chooserXml = ''
    $center = $null
    $target = $null
    for ($attempt = 0; $attempt -lt 15 -and -not $center; $attempt++) {
        Wake-Device -Serial $Serial
        $chooserXml = Get-UiHierarchy -Serial $Serial
        try {
            $center = Get-UiNodeCenter -Xml $chooserXml -Text $appLabel
            $target = 'app row'
            break
        } catch {
            $moreMatch = [regex]::Match(
                $chooserXml,
                '<node[^>]*text="' +
                    [regex]::Escape($moreLabel) +
                    '"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"'
            )
            if ($moreMatch.Success) {
                $moreX = [int](
                    ([int]$moreMatch.Groups[1].Value +
                        [int]$moreMatch.Groups[3].Value) / 2
                )
                $moreY = [int](
                    ([int]$moreMatch.Groups[2].Value +
                        [int]$moreMatch.Groups[4].Value) / 2
                )
                Write-Output "Opening system chooser more tab on $Serial"
                & $script:Adb -s $Serial shell input tap $moreX $moreY | Out-Null
                $expandedXml = Wait-ForUiText `
                    -Serial $Serial `
                    -Text $appLabel `
                    -Attempts 10
                $center = Get-UiNodeCenter -Xml $expandedXml -Text $appLabel
                $target = 'app row'
                break
            }
            if ($chooserXml -match 'resource-id="android:id/button_once"') {
                $center = Get-UiNodeCenterByResourceId `
                    -Xml $chooserXml `
                    -ResourceId 'android:id/button_once'
                $target = 'Just once button'
                break
            }
            try {
                $center = Get-UiNodeCenterContaining `
                    -Xml $chooserXml `
                    -Text $appLabel
                $target = 'direct share row'
                break
            } catch {
                Start-Sleep -Seconds 1
            }
        }
    }
    if (-not $center) {
        throw "Could not find '$appLabel' in the system chooser on $Serial"
    }
    Write-Output (
        "Tapping system chooser $target at " +
        "$($center.X),$($center.Y) on $Serial"
    )
    & $script:Adb -s $Serial shell input tap $center.X $center.Y
    if ($LASTEXITCODE -ne 0) {
        throw "Could not tap the app in the system chooser on $Serial"
    }
    Start-Sleep -Seconds 1
    $afterSelect = Get-UiHierarchy -Serial $Serial
    if ($afterSelect -match 'resource-id="android:id/button_once"') {
        $confirmation = Wait-ForUiNodeEnabled `
            -Serial $Serial `
            -ResourceId 'android:id/button_once'
        $confirmCenter = Get-UiNodeCenterByResourceId `
            -Xml $confirmation `
            -ResourceId 'android:id/button_once'
        Write-Output (
            "Confirming system chooser at " +
            "$($confirmCenter.X),$($confirmCenter.Y) on $Serial"
        )
        & $script:Adb -s $Serial shell input tap $confirmCenter.X $confirmCenter.Y | Out-Null
    }
    $received = $false
    for ($attempt = 0; $attempt -lt 3 -and -not $received; $attempt++) {
        if ($attempt -gt 0) {
            & $script:Adb -s $Serial shell input tap $center.X $center.Y
        }
        for ($check = 0; $check -lt 8; $check++) {
            $xml = Get-UiHierarchy -Serial $Serial
            if ($xml -match [regex]::Escape($marker)) {
                $received = $true
                break
            }
            Start-Sleep -Seconds 1
        }
    }
    if (-not $received) {
        throw "Timed out waiting for '$marker' after system chooser selection"
    }
    Save-DeviceScreenshot -Serial $Serial `
        -Path (Join-Path $probeDirectory 'after-share.png')

    Wake-Device -Serial $Serial
    & $script:Adb -s $Serial shell am force-stop $packageName
    Invoke-OrThrow -Label "$ProfileName system chooser restart launch" -Command {
        & $script:Adb -s $Serial shell am start -W -n $componentName
    }
    Open-RestoredConversation -Serial $Serial -Marker $marker | Out-Null
    Save-DeviceScreenshot -Serial $Serial `
        -Path (Join-Path $probeDirectory 'after-restart.png')

    Write-Output (
        "Verified $ProfileName system_chooser on ${Serial}: " +
        'share panel selection delivered and persisted after force-stop'
    )
}

function Invoke-SystemProbe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfileName,
        [Parameter(Mandatory = $true)]
        [string]$Serial,
        [Parameter(Mandatory = $true)]
        [string]$ApkPath
    )

    if (-not $AllowUnverifiedDevice) {
        Assert-DeviceProfile -ProfileName $ProfileName -Serial $Serial
    }

    Wake-Device -Serial $Serial
    & $script:Adb -s $Serial install -r $ApkPath | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Could not install release APK on $Serial"
    }

    $timestamp = Get-Date -Format 'MMddHHmmss'
    $profileCode = if ($ProfileName -eq 'honor-phone') { 'H' } else { 'G' }
    $probes = @(
        @{
            Name = 'system_share'
            Action = 'android.intent.action.SEND'
            ExtraKey = 'android.intent.extra.TEXT'
        },
        @{
            Name = 'process_text'
            Action = 'android.intent.action.PROCESS_TEXT'
            ExtraKey = 'android.intent.extra.PROCESS_TEXT'
        }
    )

    foreach ($probe in $probes) {
        Assert-IntentResolver -Serial $Serial -Action $probe.Action
        $actionCode = if ($probe.Name -eq 'system_share') { 'S' } else { 'P' }
        $marker = "AI_${profileCode}_${actionCode}_$timestamp"
        $probeDirectory = Join-Path $evidenceRoot "$ProfileName\$($probe.Name)"
        New-Item -ItemType Directory -Path $probeDirectory -Force | Out-Null

        Wake-Device -Serial $Serial
        & $script:Adb -s $Serial shell am force-stop $packageName
        Invoke-OrThrow -Label "$ProfileName $($probe.Name) share launch" -Command {
            & $script:Adb -s $Serial shell am start -W `
                -a $probe.Action `
                -t text/plain `
                --es $probe.ExtraKey $marker `
                -n $componentName
        }
        Wait-ForUiText -Serial $Serial -Text $marker | Out-Null
        Save-DeviceScreenshot -Serial $Serial `
            -Path (Join-Path $probeDirectory 'after-share.png')

        Wake-Device -Serial $Serial
        & $script:Adb -s $Serial shell am force-stop $packageName
        Invoke-OrThrow -Label "$ProfileName $($probe.Name) restart launch" -Command {
            & $script:Adb -s $Serial shell am start -W -n $componentName
        }
        Open-RestoredConversation -Serial $Serial -Marker $marker | Out-Null
        Save-DeviceScreenshot -Serial $Serial `
            -Path (Join-Path $probeDirectory 'after-restart.png')

        Write-Output (
            "Verified $ProfileName $($probe.Name) on ${Serial}: " +
            'share delivered and persisted after force-stop'
        )
    }

    Invoke-ChooserProbe -ProfileName $ProfileName `
        -Serial $Serial `
        -ProfileCode $profileCode `
        -Timestamp $timestamp
}

function Invoke-PhysicalProfile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfileName,
        [Parameter(Mandatory = $true)]
        [string]$Serial
    )
    Assert-DeviceProfile -ProfileName $ProfileName -Serial $Serial
    Invoke-OrThrow -Label "$ProfileName physical acceptance" -Command {
        & $script:Flutter test integration_test/device_acceptance_physical_test.dart `
            -d $Serial `
            --dart-define=DEVICE_UNDER_TEST=$ProfileName `
            --reporter expanded
    }
}

$script:Flutter = Resolve-Flutter
$script:Adb = Resolve-Adb
$androidSdk = Resolve-AndroidSdk
if ($androidSdk) {
    $env:ANDROID_HOME = $androidSdk
}
$javaHome = Resolve-JavaHome
if ($javaHome) {
    $env:JAVA_HOME = $javaHome
}
$env:GRADLE_OPTS = '-Djavax.net.ssl.trustStoreType=WINDOWS-ROOT'

Push-Location $appRoot
try {
    if ($AllowUnverifiedDevice -and -not $SystemProbesOnly) {
        throw '-AllowUnverifiedDevice is only valid with -SystemProbesOnly.'
    }
    if ($SystemProbesOnly -and -not $HonorSerial -and -not $GalaxySerial) {
        throw '-SystemProbesOnly requires -HonorSerial and/or -GalaxySerial.'
    }

    if (-not $SkipHost -and -not $SystemProbesOnly) {
        Invoke-OrThrow -Label '100-case host acceptance matrix' -Command {
            & $script:Flutter test test/device_acceptance_100_cases_test.dart `
                --reporter expanded
        }
    }

    if (-not $SkipPhysical -and -not $SystemProbesOnly) {
        if (-not $HonorSerial -and -not $GalaxySerial) {
            throw 'Provide -HonorSerial and/or -GalaxySerial, or use -SkipPhysical.'
        }
        if ($HonorSerial) {
            Invoke-PhysicalProfile -ProfileName 'honor-phone' -Serial $HonorSerial
        }
        if ($GalaxySerial) {
            Invoke-PhysicalProfile -ProfileName 'galaxy-tab' -Serial $GalaxySerial
        }
    }

    $hasPhysicalSerials = [bool]($HonorSerial -or $GalaxySerial)
    if (-not $SkipSystemProbes -and $hasPhysicalSerials) {
        $apkPath = Resolve-ReleaseApk
        if ($HonorSerial) {
            Invoke-SystemProbe -ProfileName 'honor-phone' `
                -Serial $HonorSerial `
                -ApkPath $apkPath
        }
        if ($GalaxySerial) {
            Invoke-SystemProbe -ProfileName 'galaxy-tab' `
                -Serial $GalaxySerial `
                -ApkPath $apkPath
        }
    }
}
finally {
    Pop-Location
}

Write-Output 'Device acceptance verification passed.'
