param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('phone', 'tablet')]
    [string]$DeviceProfile,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^(emulator-\d+|127\.0\.0\.1:\d+)$')]
    [string]$DeviceSerial,

    [Parameter(Mandatory = $true)]
    [ValidateSet('longrun', 'force_stop_recovery', 'activity_recreate', 'service_interrupted', 'service_timeout', 'service_restricted', 'notification_denied', 'secretary_matrix')]
    [string]$Scenario,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$ExpectedSourceManifestHash,

    [int]$DurationSeconds = 900,

    [string]$CaseIds = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$appRoot = Join-Path $repoRoot 'app'
$resultRoot = Join-Path $repoRoot 'test-results/secretary-agent-implementation/luna-c'
$runtimeSdk = 'D:\Dsk\timelock\.local\android-sdk'
$buildSdk = 'D:\Flutter-recovery-3.47.6\ui-fix-review-20261025\android-sdk'
$flutter = 'D:\Flutter-recovery-3.47.6\sdk\flutter\bin\flutter.bat'
$javaHome = 'C:\Program Files\Java\jdk-17.0.2'
$adb = Join-Path $runtimeSdk 'platform-tools\adb.exe'
$packageName = 'com.yuanfang.aitext.personal_ai_inbox'
$serial = $DeviceSerial
$avdName = if ($DeviceProfile -eq 'phone') { 'aitext_agent_c_phone' } else { 'aitext_agent_c_tablet' }

function Get-NotificationPermissionSampleFacts([string]$PackageDump) {
    if ([string]::IsNullOrWhiteSpace($PackageDump)) {
        return [pscustomobject]@{ FieldCount = 0; State = ''; RawLines = @() }
    }
    $permissionLines = [regex]::Matches(
        $PackageDump,
        '(?m)^[\t ]*android\.permission\.POST_NOTIFICATIONS:[\t ]*granted=(true|false)(?:[\t ]|,|$)[^\r\n]*'
    )
    $rawLines = @($PackageDump -split "`r?`n" | Where-Object { $_ -match 'POST_NOTIFICATIONS' })
    $flagMatches = if ($permissionLines.Count -eq 1) {
        [regex]::Matches($permissionLines[0].Value, 'flags=\[([^\]]*)\]')
    } else { @() }
    $flags = @()
    if ($flagMatches.Count -eq 1 -and -not [string]::IsNullOrWhiteSpace($flagMatches[0].Groups[1].Value)) {
        $flags = @($flagMatches[0].Groups[1].Value -split '[|,\s]+' | Where-Object { $_ })
    }
    [pscustomobject]@{
        FieldCount = $permissionLines.Count
        State = if ($permissionLines.Count -eq 1 -and $permissionLines[0].Groups[1].Value -eq 'true') { 'granted' } elseif ($permissionLines.Count -eq 1) { 'denied' } else { '' }
        FlagFieldCount = $flagMatches.Count
        Flags = $flags
        UserSet = $flags -contains 'USER_SET'
        UserFixed = $flags -contains 'USER_FIXED'
        RawLines = $rawLines
    }
}

function ConvertFrom-NotificationPermissionDump([string]$PackageDump) {
    $facts = Get-NotificationPermissionSampleFacts $PackageDump
    if ($facts.FieldCount -ne 1) {
        throw "Expected exactly one POST_NOTIFICATIONS granted state in package dump; found $($facts.FieldCount)."
    }
    return $facts.State
}

function Get-NotificationPermissionState([string]$AdbPath, [string]$DeviceSerial, [string]$Package) {
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $packageDump = @(& $AdbPath -P 5041 -s $DeviceSerial shell dumpsys package $Package 2>&1)
        $adbExit = $LASTEXITCODE
        if ($adbExit -ne 0) {
            throw "Could not read package permission state from $DeviceSerial (adb exit $adbExit)."
        }
        $facts = Get-NotificationPermissionSampleFacts ($packageDump -join "`n")
        "notification_permission_read_attempt=$attempt field_count=$($facts.FieldCount) raw_lines=$($facts.RawLines -join ' || ')" | Add-Content -LiteralPath $runLog
        if ($facts.FieldCount -eq 1) { return $facts.State }
        if ($facts.FieldCount -gt 1) {
            throw "Package permission dump contains $($facts.FieldCount) POST_NOTIFICATIONS states; refusing ambiguous permission handling."
        }
        if ($attempt -lt 3) { Start-Sleep -Seconds 1 }
    }
    throw 'POST_NOTIFICATIONS state remained unavailable after three successful package dumps; refusing to change permissions or app-ops.'
}

function Get-NotificationPermissionSnapshot([string]$AdbPath, [string]$DeviceSerial, [string]$Package) {
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $packageDump = @(& $AdbPath -P 5041 -s $DeviceSerial shell dumpsys package $Package 2>&1)
        $adbExit = $LASTEXITCODE
        if ($adbExit -ne 0) { throw "Could not read permission flags from $DeviceSerial (adb exit $adbExit)." }
        $facts = Get-NotificationPermissionSampleFacts ($packageDump -join "`n")
        "notification_permission_snapshot_attempt=$attempt field_count=$($facts.FieldCount) flag_field_count=$($facts.FlagFieldCount) raw_lines=$($facts.RawLines -join ' || ')" | Add-Content -LiteralPath $runLog
        if ($facts.FieldCount -gt 1) { throw 'Permission snapshot contains duplicate POST_NOTIFICATIONS entries.' }
        if ($facts.FieldCount -eq 1 -and $facts.FlagFieldCount -eq 1) {
            return [pscustomobject]@{
                State = $facts.State
                UserSet = [bool]$facts.UserSet
                UserFixed = [bool]$facts.UserFixed
                Flags = @($facts.Flags)
                RawLines = @($facts.RawLines)
            }
        }
        if ($attempt -lt 3) { Start-Sleep -Seconds 1 }
    }
    throw 'POST_NOTIFICATIONS permission flags remained unavailable; refusing state changes.'
}

function Set-NotificationPermissionFlag([string]$AdbPath, [string]$DeviceSerial, [string]$Package, [string]$Flag, [bool]$Enabled) {
    $verb = if ($Enabled) { 'set' } else { 'clear' }
    & $AdbPath -P 5041 -s $DeviceSerial shell pm "$($verb)-permission-flags" $Package android.permission.POST_NOTIFICATIONS $Flag | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Could not $verb POST_NOTIFICATIONS flag $Flag (adb exit $LASTEXITCODE)." }
}

function Restore-NotificationPermissionSnapshot([string]$AdbPath, [string]$DeviceSerial, [string]$Package, $Snapshot) {
    if ($Snapshot.State -eq 'granted') {
        & $AdbPath -P 5041 -s $DeviceSerial shell pm grant $Package android.permission.POST_NOTIFICATIONS | Out-Null
    } else {
        & $AdbPath -P 5041 -s $DeviceSerial shell pm revoke $Package android.permission.POST_NOTIFICATIONS | Out-Null
    }
    if ($LASTEXITCODE -ne 0) { throw 'Could not restore captured POST_NOTIFICATIONS grant state.' }
    Set-NotificationPermissionFlag $AdbPath $DeviceSerial $Package 'user-set' $false
    Set-NotificationPermissionFlag $AdbPath $DeviceSerial $Package 'user-fixed' $false
    if ($Snapshot.UserSet) { Set-NotificationPermissionFlag $AdbPath $DeviceSerial $Package 'user-set' $true }
    if ($Snapshot.UserFixed) { Set-NotificationPermissionFlag $AdbPath $DeviceSerial $Package 'user-fixed' $true }
    $restored = Get-NotificationPermissionSnapshot $AdbPath $DeviceSerial $Package
    if ($restored.State -ne $Snapshot.State -or $restored.UserSet -ne $Snapshot.UserSet -or $restored.UserFixed -ne $Snapshot.UserFixed) {
        throw "POST_NOTIFICATIONS did not restore exactly: state=$($restored.State), USER_SET=$($restored.UserSet), USER_FIXED=$($restored.UserFixed)."
    }
    return $restored
}

function Send-NotificationDeniedPermissionBarrierAck([int]$HostPort) {
    $handler = [System.Net.Http.HttpClientHandler]::new()
    $handler.UseProxy = $false
    $client = [System.Net.Http.HttpClient]::new($handler)
    try {
        $response = $client.PostAsync("http://127.0.0.1:$HostPort/__acceptance/notification_denied_permission", [System.Net.Http.StringContent]::new('')).GetAwaiter().GetResult()
        $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        if ([int]$response.StatusCode -ne 200 -or $body -ne 'ack') {
            throw "Notification permission barrier returned HTTP $([int]$response.StatusCode) body '$body'."
        }
    } finally {
        $client.Dispose()
        $handler.Dispose()
    }
}

function Test-NotificationPermissionDialogActive([string]$AdbPath, [string]$DeviceSerial) {
    $activityDump = @(& $AdbPath -P 5041 -s $DeviceSerial shell dumpsys activity activities 2>&1)
    $adbExit = $LASTEXITCODE
    if ($adbExit -ne 0) { throw "Could not inspect active permission dialog (adb exit $adbExit)." }
    $text = $activityDump -join "`n"
    $topResumed = [regex]::Matches($text, '(?m)^\s*topResumedActivity=.*(?:com\.android|com\.google\.android)\.permissioncontroller.*GrantPermissionsActivity')
    $resumed = [regex]::Matches($text, '(?m)^\s*mResumedActivity:\s*ActivityRecord\{[^\r\n]*(?:com\.android|com\.google\.android)\.permissioncontroller[^\r\n]*GrantPermissionsActivity')
    if ($topResumed.Count -gt 1 -or $resumed.Count -gt 1) { throw 'Activity dump contains ambiguous active permission-dialog records.' }
    return ($topResumed.Count -eq 1 -or $resumed.Count -eq 1)
}

function Deny-NotificationPermissionDialog([string]$AdbPath, [string]$DeviceSerial) {
    $remotePath = '/sdcard/agent-acceptance-permission-window.xml'
    try {
        $hierarchy = $null
        $buttons = @()
        for ($attempt = 1; $attempt -le 6; $attempt++) {
            $dump = @(& $AdbPath -P 5041 -s $DeviceSerial shell uiautomator dump $remotePath 2>&1)
            $dumpExit = $LASTEXITCODE
            if ($dumpExit -ne 0) {
                throw "Could not capture the active permission dialog hierarchy (adb exit $dumpExit): $($dump -join ' ')."
            }
            $xmlLines = @(& $AdbPath -P 5041 -s $DeviceSerial shell cat $remotePath 2>&1)
            $xmlExit = $LASTEXITCODE
            if ($xmlExit -ne 0) { throw "Could not read permission dialog hierarchy (adb exit $xmlExit)." }
            try { [xml]$hierarchy = $xmlLines -join "`n" } catch { throw 'Permission dialog hierarchy was not valid XML.' }

            # PermissionController variants expose the denial control through
            # different widget classes. Match semantic text on any clickable
            # node, then prefer an exact denial label if multiple nodes match.
            $candidates = @($hierarchy.SelectNodes('//node') | Where-Object {
                $_.GetAttribute('clickable') -eq 'true' -and
                (
                    $_.GetAttribute('text') -match "(?i)^(don[’']?t allow|not allow|不允许|拒绝)$" -or
                    $_.GetAttribute('resource-id') -match '(?i)(deny|not_allow|dont_allow)'
                )
            })
            $buttons = @($candidates | Where-Object {
                $_.GetAttribute('text') -match "(?i)^(don[’']?t allow|not allow|不允许|拒绝)$"
            })
            if ($buttons.Count -eq 0) {
                $buttons = $candidates
            }
            if ($buttons.Count -gt 0) { break }
            Start-Sleep -Milliseconds 300
        }
        if ($buttons.Count -ne 1) {
            $nodeSummary = @($hierarchy.SelectNodes('//node') | Where-Object {
                -not [string]::IsNullOrWhiteSpace($_.GetAttribute('text')) -or
                $_.GetAttribute('clickable') -eq 'true'
            } | ForEach-Object {
                "class=$($_.GetAttribute('class')) text=$($_.GetAttribute('text')) resource_id=$($_.GetAttribute('resource-id')) clickable=$($_.GetAttribute('clickable')) bounds=$($_.GetAttribute('bounds'))"
            })
            "notification_dialog_button_error candidates=$($candidates.Count) buttons=$($buttons.Count) nodes=$($nodeSummary -join ' || ')" | Add-Content -LiteralPath $runLog
            $dialogEvidence = Join-Path (Split-Path -Parent $runLog) 'notification-permission-dialog.xml'
            $xmlLines | Set-Content -LiteralPath $dialogEvidence
            "notification_dialog_hierarchy=$dialogEvidence" | Add-Content -LiteralPath $runLog
            throw "Expected one clickable notification-denial button, found $($buttons.Count)."
        }
        $button = $buttons[0]
        $bounds = [regex]::Match($button.GetAttribute('bounds'), '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$')
        if (-not $bounds.Success) { throw 'Permission denial button had missing or invalid screen bounds.' }
        $left = [int]$bounds.Groups[1].Value
        $top = [int]$bounds.Groups[2].Value
        $right = [int]$bounds.Groups[3].Value
        $bottom = [int]$bounds.Groups[4].Value
        if ($right -le $left -or $bottom -le $top) { throw 'Permission denial button bounds were empty.' }
        $x = [int](($left + $right) / 2)
        $y = [int](($top + $bottom) / 2)
        & $AdbPath -P 5041 -s $DeviceSerial shell input tap $x $y | Out-Null
        $tapExit = $LASTEXITCODE
        if ($tapExit -ne 0) { throw "Could not select notification denial (adb exit $tapExit)." }
        Start-Sleep -Milliseconds 400
        if (Test-NotificationPermissionDialogActive $AdbPath $DeviceSerial) {
            throw 'Notification permission dialog remained active after selecting denial.'
        }
        return [pscustomobject]@{ Label = $button.GetAttribute('text'); X = $x; Y = $y }
    } finally {
        & $AdbPath -P 5041 -s $DeviceSerial shell rm -f $remotePath | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Could not remove the temporary permission dialog hierarchy from the emulator.' }
    }
}

function ConvertFrom-AppOpSnapshots([string]$GetText, [string]$DumpText, [string]$Operation) {
    $escapedOperation = [regex]::Escape($Operation)
    $uidOperationLines = [regex]::Matches($GetText, "(?m)^[ `t]*Uid mode:[ `t]*${escapedOperation}:[^\r\n]*$")
    $effectiveOperationLines = [regex]::Matches($GetText, "(?m)^[ `t]*${escapedOperation}:[^\r\n]*$")
    $uidMatches = [regex]::Matches($GetText, "(?m)^[ `t]*Uid mode:[ `t]*${escapedOperation}:[ `t]*(allow|ignore|deny|default)(?:;|[ `t]|$)")
    $effectiveMatches = [regex]::Matches($GetText, "(?m)^[ `t]*${escapedOperation}:[ `t]*(allow|ignore|deny|default)(?:;|[ `t]|$)")
    $packageMatches = [regex]::Matches($DumpText, "(?m)^[ `t]*${escapedOperation}[ `t]+\((allow|ignore|deny|default)\):[ `t]*$")
    $packageOperationLines = [regex]::Matches($DumpText, "(?m)^[ `t]*${escapedOperation}\b[^\r\n]*$")
    if ($uidMatches.Count -gt 1 -or $effectiveMatches.Count -gt 1 -or $packageMatches.Count -gt 1) {
        throw "App-op snapshots for $Operation contain duplicate UID, effective, or package modes."
    }
    if ($uidOperationLines.Count -gt $uidMatches.Count -or $effectiveOperationLines.Count -gt $effectiveMatches.Count) {
        throw "App-op get output for $Operation contains an unrecognized or ambiguous mode line."
    }
    if ($packageOperationLines.Count -gt $packageMatches.Count) {
        throw "Package app-op output for $Operation contains an unrecognized or ambiguous mode line."
    }
    if ($uidMatches.Count -eq 0 -and $effectiveMatches.Count -eq 0 -and $GetText -notmatch '(?i)No operations\.?') {
        throw "App-op get output for $Operation has no recognizable UID or effective mode."
    }
    $uidMode = if ($uidMatches.Count -eq 1) { $uidMatches[0].Groups[1].Value } else { 'default' }
    $effectivePackageMode = if ($effectiveMatches.Count -eq 1) { $effectiveMatches[0].Groups[1].Value } else { $null }
    $packageMode = if ($packageMatches.Count -eq 1) { $packageMatches[0].Groups[1].Value } else { 'default' }
    $effectiveMode = if ($uidMode -ne 'default') { $uidMode } elseif ($null -ne $effectivePackageMode) { $effectivePackageMode } else { $packageMode }
    [pscustomobject]@{
        UidMode = $uidMode
        PackageMode = $packageMode
        EffectiveMode = $effectiveMode
        Raw = "appops_get=[$GetText] appops_dump=[$DumpText]"
    }
}

function Get-PackageAppOpSection([string]$DumpText, [string]$Package) {
    if ($DumpText -match '(?i)Unknown command:') {
        throw 'dumpsys appops returned an unknown-command response; refusing to infer stored app-op modes.'
    }
    $packageHeader = '(?m)^\s*Package\s+' + [regex]::Escape($Package) + ':\s*$'
    $packageMatches = [regex]::Matches($DumpText, $packageHeader)
    if ($packageMatches.Count -ne 1) {
        throw "Expected one exact Package $Package section in dumpsys appops, found $($packageMatches.Count)."
    }
    $sectionStart = $packageMatches[0].Index
    $sectionTail = $DumpText.Substring($sectionStart)
    $nextSection = [regex]::Match($sectionTail.Substring($packageMatches[0].Length), '(?m)^\s*(?:Package\s+[^:]+:|Uid\s+u[0-9a-z]+:|AppOps policy )')
    $sectionLength = if ($nextSection.Success) {
        $packageMatches[0].Length + $nextSection.Index
    } else {
        $sectionTail.Length
    }
    return $sectionTail.Substring(0, $sectionLength)
}

function Get-AppOpState([string]$AdbPath, [string]$DeviceSerial, [string]$Package, [string]$Operation) {
    $getOutput = @(& $AdbPath -P 5041 -s $DeviceSerial shell appops get $Package $Operation 2>&1)
    $getExitCode = $LASTEXITCODE
    if ($getExitCode -ne 0) {
        throw "Could not read $Operation effective app-op state from $DeviceSerial (adb exit $getExitCode)."
    }
    $dumpOutput = @(& $AdbPath -P 5041 -s $DeviceSerial shell dumpsys appops 2>&1)
    $dumpExitCode = $LASTEXITCODE
    if ($dumpExitCode -ne 0) {
        throw "Could not read $Operation stored app-op mode from $DeviceSerial (adb exit $dumpExitCode)."
    }
    $dumpText = $dumpOutput -join "`n"
    $packageSection = Get-PackageAppOpSection -DumpText $dumpText -Package $Package
    $state = ConvertFrom-AppOpSnapshots ($getOutput -join "`n") $packageSection $Operation
    $state | Add-Member -NotePropertyName GetExitCode -NotePropertyValue $getExitCode
    $state | Add-Member -NotePropertyName DumpExitCode -NotePropertyValue $dumpExitCode
    return $state
}

function Assert-AppOpStateExact($Expected, $Actual, [string]$Operation) {
    if ($Expected.UidMode -ne $Actual.UidMode -or
        $Expected.PackageMode -ne $Actual.PackageMode -or
        $Expected.EffectiveMode -ne $Actual.EffectiveMode) {
        throw "Stored $Operation app-op readback mismatch: expected UID=$($Expected.UidMode), package=$($Expected.PackageMode), effective=$($Expected.EffectiveMode); actual UID=$($Actual.UidMode), package=$($Actual.PackageMode), effective=$($Actual.EffectiveMode); raw=$($Actual.Raw)"
    }
}

function Set-PackageAppOpState(
    [string]$AdbPath,
    [string]$DeviceSerial,
    [string]$Package,
    [string]$Operation,
    [string]$PackageMode,
    $CapturedState
) {
    if ($Operation -ne 'START_FOREGROUND') {
        throw "Package-layer AppOp writes are restricted to START_FOREGROUND; refusing $Operation."
    }
    if ($PackageMode -notin @('allow', 'ignore', 'deny', 'default')) {
        throw "Unsupported package START_FOREGROUND mode '$PackageMode'."
    }
    if ($CapturedState.UidMode -ne 'default') {
        throw "START_FOREGROUND UID baseline is '$($CapturedState.UidMode)'; package-layer injection requires captured UID=default."
    }

    $before = Get-AppOpState $AdbPath $DeviceSerial $Package $Operation
    if ($before.UidMode -ne 'default') {
        throw "START_FOREGROUND UID mode changed to '$($before.UidMode)' before package-layer write; refusing mixed-layer mutation."
    }
    & $AdbPath -P 5041 -s $DeviceSerial shell appops set $Package $Operation $PackageMode | Out-Null
    $packageSetExitCode = $LASTEXITCODE
    if ($packageSetExitCode -ne 0) {
        $failure = "Could not set package START_FOREGROUND app-op to $PackageMode (adb exit $packageSetExitCode)."
        if ($script:runLog) { "package_appop_write_failure=$failure" | Add-Content -LiteralPath $script:runLog }
        if ($null -ne $script:outerCleanupFailures) { $script:outerCleanupFailures.Add("package_appop_write_failure=$failure") }
        throw $failure
    }

    $actual = Get-AppOpState $AdbPath $DeviceSerial $Package $Operation
    $expectedEffectiveMode = if ($PackageMode -eq 'default') { 'default' } else { $PackageMode }
    $expected = [pscustomobject]@{
        UidMode = 'default'
        PackageMode = $PackageMode
        EffectiveMode = $expectedEffectiveMode
        Raw = 'package-only START_FOREGROUND write'
    }
    "package_appop_state_readback operation=$Operation package_set_exit=$packageSetExitCode get_exit=$($actual.GetExitCode) dumpsys_exit=$($actual.DumpExitCode) expected_uid=default expected_package=$PackageMode expected_effective=$expectedEffectiveMode actual_uid=$($actual.UidMode) actual_package=$($actual.PackageMode) actual_effective=$($actual.EffectiveMode)" | Add-Content -LiteralPath $script:runLog
    try {
        Assert-AppOpStateExact -Expected $expected -Actual $actual -Operation $Operation
    } catch {
        $failure = $_.Exception.Message
        if ($script:runLog) { "package_appop_readback_failure=$failure" | Add-Content -LiteralPath $script:runLog }
        if ($null -ne $script:outerCleanupFailures) {
            $script:outerCleanupFailures.Add("package_appop_readback_failure=$failure")
        }
        throw $failure
    }
    return $actual
}

function Get-NotificationPermissionAppOpExpectation($CapturedPermission, $CapturedAppOp, [string]$TargetPermission) {
    if ($TargetPermission -notin @('granted', 'denied')) {
        throw "Unsupported POST_NOTIFICATIONS target permission '$TargetPermission'."
    }
    if ($CapturedAppOp.PackageMode -ne 'default') {
        throw "POST_NOTIFICATION package AppOp baseline is '$($CapturedAppOp.PackageMode)'; runtime permission handling will not rewrite package mode."
    }
    if ($TargetPermission -eq $CapturedPermission) {
        return [pscustomobject]@{
            UidMode = $CapturedAppOp.UidMode
            PackageMode = $CapturedAppOp.PackageMode
            EffectiveMode = $CapturedAppOp.EffectiveMode
            Raw = $CapturedAppOp.Raw
        }
    }
    if ($CapturedPermission -eq 'denied' -and $TargetPermission -eq 'granted') {
        if ($CapturedAppOp.UidMode -ne 'ignore' -or $CapturedAppOp.EffectiveMode -ne 'ignore') {
            throw "Denied POST_NOTIFICATIONS baseline must be UID=ignore/package=default/effective=ignore before granting; got UID=$($CapturedAppOp.UidMode), package=$($CapturedAppOp.PackageMode), effective=$($CapturedAppOp.EffectiveMode)."
        }
        return [pscustomobject]@{ UidMode = 'default'; PackageMode = 'default'; EffectiveMode = 'default'; Raw = 'runtime permission grant projection' }
    }
    if ($CapturedPermission -eq 'granted' -and $TargetPermission -eq 'denied') {
        return [pscustomobject]@{ UidMode = 'ignore'; PackageMode = 'default'; EffectiveMode = 'ignore'; Raw = 'runtime permission revoke projection' }
    }
    throw "Unsupported POST_NOTIFICATIONS transition '$CapturedPermission' -> '$TargetPermission'."
}

function Set-NotificationPermissionState(
    [string]$AdbPath,
    [string]$DeviceSerial,
    [string]$Package,
    [string]$TargetPermission,
    [string]$CapturedPermission,
    $CapturedAppOp
) {
    $expectedAppOp = Get-NotificationPermissionAppOpExpectation $CapturedPermission $CapturedAppOp $TargetPermission
    $permissionBeforeWrite = Get-NotificationPermissionState $AdbPath $DeviceSerial $Package
    if ($TargetPermission -ne $permissionBeforeWrite) {
        $verb = if ($TargetPermission -eq 'granted') { 'grant' } else { 'revoke' }
        & $AdbPath -P 5041 -s $DeviceSerial shell pm $verb $Package android.permission.POST_NOTIFICATIONS | Out-Null
        $permissionSetExitCode = $LASTEXITCODE
        if ($permissionSetExitCode -ne 0) {
            $failure = "Could not $verb POST_NOTIFICATIONS (adb exit $permissionSetExitCode)."
            if ($script:runLog) { "notification_permission_write_failure=$failure" | Add-Content -LiteralPath $script:runLog }
            if ($null -ne $script:outerCleanupFailures) { $script:outerCleanupFailures.Add("notification_permission_write_failure=$failure") }
            throw $failure
        }
    } else {
        $permissionSetExitCode = 0
    }

    $actualPermission = Get-NotificationPermissionState $AdbPath $DeviceSerial $Package
    if ($actualPermission -ne $TargetPermission) {
        throw "POST_NOTIFICATIONS permission readback mismatch: expected $TargetPermission, got $actualPermission."
    }
    $actualAppOp = Get-AppOpState $AdbPath $DeviceSerial $Package 'POST_NOTIFICATION'
    "notification_permission_appop_readback permission_write_exit=$permissionSetExitCode expected_permission=$TargetPermission actual_permission=$actualPermission expected_uid=$($expectedAppOp.UidMode) expected_package=$($expectedAppOp.PackageMode) expected_effective=$($expectedAppOp.EffectiveMode) actual_uid=$($actualAppOp.UidMode) actual_package=$($actualAppOp.PackageMode) actual_effective=$($actualAppOp.EffectiveMode)" | Add-Content -LiteralPath $script:runLog
    Assert-AppOpStateExact -Expected $expectedAppOp -Actual $actualAppOp -Operation 'POST_NOTIFICATION'
    return [pscustomobject]@{ Permission = $actualPermission; AppOp = $actualAppOp }
}

function Get-AppOpEffectiveMode($State) {
    return $State.EffectiveMode
}

function Test-AppOpStateEqual($Left, $Right) {
    return (($Left.UidMode -eq $Right.UidMode) -and
        ($Left.PackageMode -eq $Right.PackageMode) -and
        ($Left.EffectiveMode -eq $Right.EffectiveMode))
}

function New-ServiceRestrictionMonitorState {
    return [pscustomobject]@{
        StartAckAt = $null
        DenialObserved = $false
        ActivityThawed = $false
        ActivityThawedAt = $null
        ReadyDeadline = $null
        ResumeAckAt = $null
        ReadyAssistantId = $null
        ReadyTaskId = $null
        ReadyObservedAt = $null
        BackgroundUidState = $null
        FailureEvidenceAttempted = $false
        FailureEvidenceExported = $false
    }
}

function ConvertFrom-ServiceRestrictedReadyIdentity([string]$Output) {
    $markerLines = [regex]::Matches(
        $Output,
        '(?m)^AGENT_SERVICE_RESTRICTED_READY[^\r\n]*$'
    )
    if ($markerLines.Count -ne 1) {
        throw "Expected exactly one service-restricted READY marker line; found $($markerLines.Count)."
    }
    $matches = [regex]::Matches(
        $Output,
        '(?m)^AGENT_SERVICE_RESTRICTED_READY\|([^|\r\n]+)\|([^|\r\n]+)[\t ]*$'
    )
    if ($matches.Count -ne 1) {
        throw "Expected exactly one service-restricted READY marker with assistant and task IDs; found $($matches.Count)."
    }
    return [pscustomobject]@{
        AssistantId = $matches[0].Groups[1].Value
        TaskId = $matches[0].Groups[2].Value
    }
}

function Assert-ServiceRestrictedResultIdentity($ReadyIdentity, [string]$Output) {
    if ($null -eq $ReadyIdentity -or
        [string]::IsNullOrWhiteSpace([string]$ReadyIdentity.AssistantId) -or
        [string]::IsNullOrWhiteSpace([string]$ReadyIdentity.TaskId)) {
        throw 'Service-restricted READY identity must contain assistant and durable task IDs.'
    }
    $markerLines = [regex]::Matches(
        $Output,
        '(?m)^AGENT_SERVICE_RESTRICTED_RESULT[^\r\n]*$'
    )
    if ($markerLines.Count -ne 1) {
        throw "Expected exactly one service-restricted RESULT marker line; found $($markerLines.Count)."
    }
    $matches = [regex]::Matches(
        $Output,
        '(?m)^AGENT_SERVICE_RESTRICTED_RESULT\|[^|\r\n]+\|[^|\r\n]+\|([^|\r\n]+)\|([^|\r\n]+)\|[^|\r\n]+\|passed[\t ]*$'
    )
    if ($matches.Count -ne 1) {
        throw "Expected exactly one passed service-restricted result marker; found $($matches.Count)."
    }
    $assistantId = $matches[0].Groups[1].Value
    $taskId = $matches[0].Groups[2].Value
    if ($assistantId -ne [string]$ReadyIdentity.AssistantId) {
        throw 'Service-restricted result assistant ID did not match READY.'
    }
    if ($taskId -ne [string]$ReadyIdentity.TaskId) {
        throw 'Service-restricted result durable task ID did not match READY.'
    }
    return [pscustomobject]@{ AssistantId = $assistantId; TaskId = $taskId }
}

function Get-PackageAppId([string]$DeviceSerial, [string]$Package) {
    $packageDump = @(& $adb -P 5041 -s $DeviceSerial shell dumpsys package $Package 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Could not read appId for $Package." }
    $matches = [regex]::Matches(($packageDump -join "`n"), '(?m)^\s*appId=(\d+)\s*$')
    if ($matches.Count -ne 1) { throw "Expected one appId for $Package, found $($matches.Count)." }
    return $matches[0].Groups[1].Value
}

function Get-TargetActivityRecordFacts([string]$ActivityText, [string]$Package) {
    $componentPattern = [regex]::Escape("$Package/.MainActivity")
    $lines = @($ActivityText -split "`n")
    $targetRecordLines = @($lines | Where-Object {
        $_ -match '^\s*\*\s*Hist\s*#\s*\d+:\s*ActivityRecord\{' -and
        $_ -match $componentPattern
    })
    $pausedActivityLines = @($lines | Where-Object {
        $_ -match '^\s*mLastPausedActivity:\s*ActivityRecord\{' -and
        $_ -match $componentPattern
    })
    $topResumedActivityLines = @($lines | Where-Object {
        $_ -match '^\s*topResumedActivity=\s*ActivityRecord\{' -and
        $_ -match $componentPattern
    })
    if ($targetRecordLines.Count -gt 1 -or $pausedActivityLines.Count -gt 1 -or $topResumedActivityLines.Count -gt 1) {
        throw "Activity dump contains duplicate target MainActivity records for $Package."
    }
    [pscustomobject]@{
        MainActivityRecord = if ($targetRecordLines.Count -eq 1) { $targetRecordLines[0].Trim() } else { '' }
        MainActivityPaused = $pausedActivityLines.Count -eq 1
        MainActivityResumed = $topResumedActivityLines.Count -eq 1
    }
}

function Get-ActivityPlacementSnapshot([string]$DeviceSerial, [string]$Package) {
    $activityDump = @(& $adb -P 5041 -s $DeviceSerial shell dumpsys activity activities 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Could not inspect Activity placement on $DeviceSerial." }
    $activityText = $activityDump -join "`n"
    $appId = Get-PackageAppId $DeviceSerial $Package
    $uidStateOutput = @(& $adb -P 5041 -s $DeviceSerial shell cmd activity get-uid-state $appId 2>&1)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($uidStateOutput -join ' '))) {
        throw "Could not read process state for appId $appId."
    }
    $activityFacts = Get-TargetActivityRecordFacts $activityText $Package
    [pscustomobject]@{
        AppId = $appId
        UidState = ($uidStateOutput -join ' ').Trim()
        TopResumedNexus = ($activityText -match '(?m)topResumedActivity=.*NexusLauncherActivity')
        TopResumedApp = ($activityText -match "(?m)topResumedActivity=.*$([regex]::Escape($Package)).*MainActivity")
        MainActivityRecord = $activityFacts.MainActivityRecord
        MainActivityPaused = $activityFacts.MainActivityPaused
        MainActivityResumed = $activityFacts.MainActivityResumed
    }
}

function Test-ActivityPlacementSnapshot($Snapshot, [ValidateSet('background', 'foreground')][string]$Placement) {
    if ([string]::IsNullOrWhiteSpace([string]$Snapshot.MainActivityRecord)) { return $false }
    $uidIsTop = $Snapshot.UidState -match '\(TOP(?:_SLEEPING)?\)'
    if ($Placement -eq 'background') {
        return ($Snapshot.TopResumedNexus -and $Snapshot.MainActivityPaused -and -not $uidIsTop)
    }
    return ($Snapshot.TopResumedApp -and $Snapshot.MainActivityResumed -and $uidIsTop)
}

function ConvertFrom-DisplayLockDump([string]$PowerText, [string]$PolicyText) {
    $screenStateMatches = [regex]::Matches($PolicyText, '(?m)^\s*screenState=SCREEN_STATE_(ON|OFF|GOING_TO_SLEEP|GOING_TO_WAKE)\s*$')
    $interactiveStateMatches = [regex]::Matches($PolicyText, '(?m)^\s*interactiveState=INTERACTIVE_STATE_(AWAKE|ASLEEP|GOING_TO_SLEEP|GOING_TO_WAKE)\s*$')
    $interactiveMatches = [regex]::Matches($PowerText, '(?m)^\s*mInteractive=(true|false)\s*$')
    $delegateMatches = [regex]::Matches($PolicyText, '(?m)^\s{6}showing=(true|false)\s*$')
    $monitorMatches = [regex]::Matches($PolicyText, '(?m)^\s*mIsShowing=(true|false)\s*$')
    if ($screenStateMatches.Count -gt 1 -or $interactiveStateMatches.Count -gt 1 -or $interactiveMatches.Count -gt 1 -or
        $delegateMatches.Count -gt 1 -or $monitorMatches.Count -gt 1) {
        throw "Display/keyguard dump contains duplicate source fields; counts=$($screenStateMatches.Count)/$($interactiveStateMatches.Count)/$($interactiveMatches.Count)/$($delegateMatches.Count)/$($monitorMatches.Count)."
    }
    if ($screenStateMatches.Count -eq 0 -and $interactiveStateMatches.Count -eq 0 -and $interactiveMatches.Count -eq 0) {
        throw 'No supported screenState, interactiveState, or legacy mInteractive is present.'
    }
    if ($delegateMatches.Count -eq 0 -and $monitorMatches.Count -eq 0) {
        throw 'No supported KeyguardServiceDelegate showing or KeyguardStateMonitor mIsShowing field is present.'
    }
    $screenState = if ($screenStateMatches.Count -eq 1) { $screenStateMatches[0].Groups[1].Value } else { '' }
    $screenOn = if ($screenState -eq 'ON') { $true } elseif ($screenState -eq 'OFF') { $false } else { $null }
    $interactiveState = if ($interactiveStateMatches.Count -eq 1) { $interactiveStateMatches[0].Groups[1].Value } else { '' }
    $interactiveFromState = if ($interactiveState -eq 'AWAKE') { $true } elseif ($interactiveState -eq 'ASLEEP') { $false } else { $null }
    $legacyInteractive = if ($interactiveMatches.Count -eq 1) { $interactiveMatches[0].Groups[1].Value -eq 'true' } else { $null }
    $transitionObserved = $screenState -in @('GOING_TO_SLEEP', 'GOING_TO_WAKE') -or
        $interactiveState -in @('GOING_TO_SLEEP', 'GOING_TO_WAKE')
    $stableInteractiveSources = @(@($screenOn, $interactiveFromState, $legacyInteractive) | Where-Object { $null -ne $_ })
    for ($index = 0; $index -lt $stableInteractiveSources.Count; $index++) {
        for ($otherIndex = $index + 1; $otherIndex -lt $stableInteractiveSources.Count; $otherIndex++) {
            if ($stableInteractiveSources[$index] -ne $stableInteractiveSources[$otherIndex]) {
                throw "screenState/interactiveState/mInteractive disagree; screen=$screenState interactiveState=$interactiveState legacy=$legacyInteractive."
            }
        }
    }
    if ($screenStateMatches.Count -eq 1 -and $null -eq $screenOn -and $interactiveMatches.Count -eq 1) {
        throw "Transitional screenState ($screenState) cannot be reconciled with legacy mInteractive."
    }
    $keyguardValues = @()
    if ($delegateMatches.Count -eq 1) { $keyguardValues += ($delegateMatches[0].Groups[1].Value -eq 'true') }
    if ($monitorMatches.Count -eq 1) { $keyguardValues += ($monitorMatches[0].Groups[1].Value -eq 'true') }
    if ($keyguardValues.Count -gt 1 -and $keyguardValues[0] -ne $keyguardValues[1]) {
        throw 'KeyguardServiceDelegate and KeyguardStateMonitor disagree; refusing display-state inference.'
    }
    if ($screenStateMatches.Count -eq 0 -and $null -ne $legacyInteractive) { $screenOn = $legacyInteractive }
    $interactive = if ($transitionObserved) { $null } elseif ($stableInteractiveSources.Count -gt 0) { $stableInteractiveSources[0] } else { $null }
    [pscustomobject]@{
        ScreenOn = $screenOn
        Interactive = $interactive
        KeyguardShowing = $keyguardValues[0]
        ScreenState = $screenState
        InteractiveState = $interactiveState
    }
}

function Get-DisplayLockSnapshot([string]$DeviceSerial) {
    $powerDump = @(& $adb -P 5041 -s $DeviceSerial shell dumpsys power 2>&1)
    $powerExit = $LASTEXITCODE
    "display_lock_read=power exit=$powerExit" | Add-Content -LiteralPath $runLog
    if ($powerExit -ne 0) { throw "Could not read display state (dumpsys power exit $powerExit)." }
    $policyDump = @(& $adb -P 5041 -s $DeviceSerial shell dumpsys window policy 2>&1)
    $policyExit = $LASTEXITCODE
    "display_lock_read=window_policy exit=$policyExit" | Add-Content -LiteralPath $runLog
    if ($policyExit -ne 0) { throw "Could not read keyguard state (dumpsys window policy exit $policyExit)." }
    $facts = ConvertFrom-DisplayLockDump ($powerDump -join "`n") ($policyDump -join "`n")
    "display_lock_state=screen:$($facts.ScreenState),interactive_state:$($facts.InteractiveState),interactive:$($facts.Interactive),screen_on:$($facts.ScreenOn),keyguard:$($facts.KeyguardShowing)" | Add-Content -LiteralPath $runLog
    return $facts
}

function Invoke-CheckedAdb([string]$Label, [string[]]$Arguments) {
    $output = @(& $adb @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    "adb_action=$Label exit=$exitCode output=$($output -join ' ')" | Add-Content -LiteralPath $runLog
    if ($exitCode -ne 0) { throw "ADB action '$Label' failed with exit ${exitCode}: $($output -join ' ')" }
    return ($output -join "`n")
}

function Wait-ActivityPlacement([string]$DeviceSerial, [string]$Package, [ValidateSet('background', 'foreground')][string]$Placement) {
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    $latest = $null
    do {
        $latest = Get-ActivityPlacementSnapshot $DeviceSerial $Package
        if (Test-ActivityPlacementSnapshot $latest $Placement) { return $latest }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Timed out verifying $Placement placement: uid=$($latest.UidState), nexusTop=$($latest.TopResumedNexus), appTop=$($latest.TopResumedApp), paused=$($latest.MainActivityPaused), resumed=$($latest.MainActivityResumed), record=$($latest.MainActivityRecord)."
}

function Test-BackgroundStartEligibility($Snapshot, [string]$AppOpMode, [double]$ElapsedSeconds) {
    if ($ElapsedSeconds -lt 15 -or $AppOpMode -ne 'ignore') { return $false }
    if (-not (Test-ActivityPlacementSnapshot $Snapshot 'background')) { return $false }
    if ($Snapshot.UidState -notmatch '^\s*\d+\s+\([A-Z_]+\)\s*$') { return $false }
    return ($Snapshot.UidState -notmatch '^\s*(?:2|3|4|5|6|7|8|12)\s+\(')
}

function Wait-BackgroundStartEligibility([string]$DeviceSerial, [string]$Package, [DateTime]$HomeSentAt) {
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    $stableSamples = 0
    $latest = $null
    $latestMode = 'unknown'
    $elapsedSeconds = 0.0
    do {
        $latest = Get-ActivityPlacementSnapshot $DeviceSerial $Package
        $appOp = Get-AppOpState $adb $DeviceSerial $Package 'START_FOREGROUND'
        $latestMode = Get-AppOpEffectiveMode $appOp
        $elapsedSeconds = ([DateTime]::UtcNow - $HomeSentAt).TotalSeconds
        if (Test-BackgroundStartEligibility $latest $latestMode $elapsedSeconds) {
            $stableSamples++
            if ($stableSamples -ge 3) {
                $latest | Add-Member -NotePropertyName BackgroundElapsedSeconds -NotePropertyValue ([Math]::Round($elapsedSeconds, 1))
                return $latest
            }
        } else {
            $stableSamples = 0
        }
        Start-Sleep -Seconds 1
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Could not prove background FGS-start eligibility before ACK: elapsed=${elapsedSeconds}s uid=$($latest.UidState) nexusTop=$($latest.TopResumedNexus) mainPaused=$($latest.MainActivityPaused) histPresent=$([bool]$latest.MainActivityRecord) appop=$latestMode stableSamples=$stableSamples."
}

function Get-TargetServiceRestrictionFacts([string]$ServicesDump, [string]$Package, [string]$AppId) {
    $componentPattern = [regex]::Escape("$Package/.DataSyncForegroundService")
    $lines = @($ServicesDump -split "`n")
    $recordIndexes = @()
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match 'ServiceRecord\{' -and $lines[$index] -match $componentPattern) {
            $recordIndexes += $index
        }
    }
    if ($recordIndexes.Count -gt 1) {
        throw "Service dump contains duplicate target DataSyncForegroundService records for $Package."
    }
    if ($recordIndexes.Count -eq 0) {
        return [pscustomobject]@{
            RecordExists = $false
            DeniedBeforeStart = $false
            ForegroundServiceActive = $false
            ServiceRecord = ''
        }
    }
    $recordStart = $recordIndexes[0]
    $recordEnd = $lines.Count - 1
    for ($index = $recordStart + 1; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '^\s*\*?\s*ServiceRecord\{') {
            $recordEnd = $index - 1
            break
        }
    }
    $record = $lines[$recordStart..$recordEnd] -join "`n"
    $appMatch = [regex]::Match($record, '(?m)^\s*app=(.*?)\s*$')
    $startCountMatch = [regex]::Match($record, '(?m)^\s*startForegroundCount=(\d+)\s*$')
    $appIsNull = $appMatch.Success -and $appMatch.Groups[1].Value.Trim() -eq 'null'
    $startCount = if ($startCountMatch.Success) { [int]$startCountMatch.Groups[1].Value } else { -1 }
    $startActionPattern = [regex]::Escape($Package + '.agent.START')
    $hasTargetStartIntent = $record -match "act=$startActionPattern" -and $record -match $componentPattern
    $hasTargetCaller = $record -match "callingUid:\s*$([regex]::Escape($AppId))(?:;|\s)"
    $deniedBeforeStart = $hasTargetStartIntent -and $hasTargetCaller -and $record -match '\bcode:DENIED\b' -and $appIsNull -and $startCount -eq 0
    $foregroundServiceActive = -not ($appIsNull -and $startCount -eq 0)
    [pscustomobject]@{
        RecordExists = $true
        DeniedBeforeStart = $deniedBeforeStart
        ForegroundServiceActive = $foregroundServiceActive
        ServiceRecord = $record
    }
}

function Copy-AdbExecOutRunAsFile([string]$AdbPath, [string]$DeviceSerial, [string]$Package, [string]$DevicePath, [string]$HostPath) {
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $AdbPath
    $startInfo.Arguments = "-P 5041 -s $DeviceSerial exec-out run-as $Package cat $DevicePath"
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($startInfo)
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $fileStream = [System.IO.File]::Open($HostPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try {
        $process.StandardOutput.BaseStream.CopyTo($fileStream)
    } finally {
        $fileStream.Dispose()
    }
    $process.WaitForExit()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    if ($process.ExitCode -ne 0) {
        throw "adb exec-out run-as cat failed (exit $($process.ExitCode)): $stderr"
    }
    $length = (Get-Item -LiteralPath $HostPath).Length
    if ($length -le 0) { throw 'adb exec-out run-as cat produced an empty archive.' }
    return $length
}

function Export-ServiceRestrictedFailureEvidence([string]$DeviceProfileName, [string]$RunToken) {
    $safeToken = [regex]::Replace($RunToken, '[^A-Za-z0-9_-]', '')
    $exportName = "acceptance-evidence-$safeToken"
    $profileRoot = "files/secretary-agent-acceptance/$DeviceProfileName"
    $deviceArchive = "/data/user/0/$packageName/files/secretary-agent-acceptance/.$exportName.tar"
    $hostArchive = Join-Path $runDir "$exportName.tar"
    $hostEvidence = Join-Path $runDir $exportName
    $deviceArchiveCreated = $false
    try {
        $packagePaths = @(& $adb -P 5041 -s $serial shell pm path $packageName 2>&1)
        if ($LASTEXITCODE -ne 0 -or @($packagePaths | Where-Object { $_ -match '^package:' }).Count -eq 0) {
            "service_restricted_failure_evidence_export=unavailable package_not_installed=true" | Add-Content -LiteralPath $runLog
            return $false
        }
        $profileCheck = @(& $adb -P 5041 -s $serial shell run-as $packageName test -d $profileRoot 2>&1)
        if ($LASTEXITCODE -ne 0) {
            "service_restricted_failure_evidence_export=failed stage=profile_preflight exit=$LASTEXITCODE output=$($profileCheck -join ' ') path=$profileRoot" | Add-Content -LiteralPath $runLog
            return $false
        }
        $deviceArchiveCreated = $true
        $archiveOutput = & $adb -P 5041 -s $serial shell run-as $packageName tar -C $profileRoot -cf $deviceArchive . 2>&1
        if ($LASTEXITCODE -ne 0) {
            "service_restricted_failure_evidence_export=failed stage=internal_archive exit=$LASTEXITCODE output=$($archiveOutput -join ' ')" | Add-Content -LiteralPath $runLog
            return $false
        }
        try {
            $archiveBytes = Copy-AdbExecOutRunAsFile $adb $serial $packageName $deviceArchive $hostArchive
        } catch {
            "service_restricted_failure_evidence_export=failed stage=exec_out_cat error=$($_.Exception.Message)" | Add-Content -LiteralPath $runLog
            return $false
        }
        New-Item -ItemType Directory -Path $hostEvidence -Force | Out-Null
        $extractOutput = & tar -xf $hostArchive -C $hostEvidence 2>&1
        if ($LASTEXITCODE -ne 0) {
            "service_restricted_failure_evidence_export=failed stage=extract exit=$LASTEXITCODE output=$($extractOutput -join ' ') archive=$hostArchive" | Add-Content -LiteralPath $runLog
            return $false
        }
        "service_restricted_failure_evidence_export=complete path=$hostEvidence archive_bytes=$archiveBytes archive_sha256=$((Get-FileHash -LiteralPath $hostArchive -Algorithm SHA256).Hash.ToLowerInvariant())" | Add-Content -LiteralPath $runLog
        return $true
    } catch {
        "service_restricted_failure_evidence_export=failed exception=$($_.Exception.Message)" | Add-Content -LiteralPath $runLog
        return $false
    } finally {
        if ($deviceArchiveCreated) {
            $removeOutput = @(& $adb -P 5041 -s $serial shell run-as $packageName rm -f $deviceArchive 2>&1)
            if ($LASTEXITCODE -ne 0) { "service_restricted_failure_archive_cleanup=failed exit=$LASTEXITCODE output=$($removeOutput -join ' ')" | Add-Content -LiteralPath $runLog }
        }
    }
}

function Invoke-LocalFixtureBarrier([string]$Path, [string]$Body, [string]$Description) {
    & $adb -P 5041 forward --remove tcp:47632 2>&1 | Out-Null
    $forwardOutput = & $adb -P 5041 forward tcp:47632 tcp:47631 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Could not establish local $Description barrier: $forwardOutput" }
    try {
        $barrierRequest = [System.Net.WebRequest]::Create("http://127.0.0.1:47632$Path")
        $barrierRequest.Proxy = $null
        $barrierRequest.Method = 'POST'
        $barrierRequest.ContentType = 'application/json'
        $barrierRequest.Timeout = 15000
        $barrierRequest.ReadWriteTimeout = 15000
        $barrierBytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
        $barrierRequest.ContentLength = $barrierBytes.Length
        $barrierStream = $barrierRequest.GetRequestStream()
        try { $barrierStream.Write($barrierBytes, 0, $barrierBytes.Length) } finally { $barrierStream.Dispose() }
        $barrierResponse = $barrierRequest.GetResponse()
        try {
            $barrierReader = [System.IO.StreamReader]::new($barrierResponse.GetResponseStream())
            try { $ack = $barrierReader.ReadToEnd() } finally { $barrierReader.Dispose() }
            if ($barrierResponse.StatusCode -ne [System.Net.HttpStatusCode]::OK -or $ack -ne 'ack') {
                throw "$Description barrier returned $($barrierResponse.StatusCode): $ack"
            }
            return $ack
        } finally { $barrierResponse.Dispose() }
    } finally {
        & $adb -P 5041 forward --remove tcp:47632 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Could not remove local $Description ADB forward." }
    }
}

if ($Scenario -eq 'longrun' -and $DurationSeconds -lt 900) {
    throw 'Longrun acceptance requires at least 900 wall-clock seconds.'
}
foreach ($requiredPath in @($flutter, $adb, $buildSdk, $javaHome)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required Android acceptance path is missing: $requiredPath"
    }
}
New-Item -ItemType Directory -Path $resultRoot -Force | Out-Null

$env:ANDROID_HOME = $buildSdk
$env:ANDROID_SDK_ROOT = $buildSdk
$env:ANDROID_ADB_SERVER_PORT = '5041'
$env:JAVA_HOME = $javaHome
$env:GRADLE_USER_HOME = 'C:\Users\18377\.gradle'
$env:Path = "$javaHome\bin;$runtimeSdk\platform-tools;$env:Path"

$deviceLines = & $adb -P 5041 devices
$connectedDevice = @($deviceLines | Where-Object { $_ -match "^$serial\s+device$" })
if ($LASTEXITCODE -ne 0 -or $connectedDevice.Count -ne 1) {
    throw "Expected isolated emulator $serial is not connected to ADB server 5041. Start only the $DeviceProfile AVD first."
}
$actualAvd = (& $adb -P 5041 -s $serial shell getprop ro.boot.qemu.avd_name).Trim()
if ($actualAvd -ne $avdName) {
    throw "Device identity mismatch: expected $avdName on $serial, found '$actualAvd'."
}
$bootCompleted = (& $adb -P 5041 -s $serial shell getprop sys.boot_completed).Trim()
if ($bootCompleted -ne '1') {
    throw "Emulator $serial has not completed Android boot."
}
$apiLevel = [int](& $adb -P 5041 -s $serial shell getprop ro.build.version.sdk).Trim()
if ($apiLevel -lt 35) {
    throw "Emulator $serial must run Android API 35 or later."
}
if ($Scenario -eq 'service_timeout' -and $apiLevel -lt 35) {
    throw 'Native dataSync timeout injection requires Android API 35 or later.'
}
$emulatorExe = 'E:\DevTools\Android\Sdk\emulator\emulator.exe'
$emulatorProcesses = @(Get-CimInstance Win32_Process | Where-Object {
    $_.Name -eq 'emulator.exe' -and $_.CommandLine -match [regex]::Escape("-avd $avdName")
})
if ($emulatorProcesses.Count -ne 1) {
    throw "Expected exactly one emulator process for $avdName; found $($emulatorProcesses.Count)."
}
$emulatorCommandLine = $emulatorProcesses[0].CommandLine
$emulatorVersion = (& $emulatorExe -version | Select-Object -First 1).Trim()

$runId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ') + "-$DeviceProfile-$Scenario"
$runDir = Join-Path $resultRoot $runId
New-Item -ItemType Directory -Path $runDir -Force | Out-Null
$runLog = Join-Path $runDir 'orchestration.log'
$sourceRoots = @(
    'app/lib',
    'app/android',
    'app/integration_test',
    'app/test/e2e/realistic_runner.dart',
    'app/test/agent_background_service_test.dart',
    'app/test/agent_background_workspace_test.dart',
    'app/test_driver/integration_test.dart',
    'app/pubspec.yaml',
    'app/pubspec.lock',
    'scripts/run-secretary-agent-android-acceptance.ps1'
)
$excludedSourceDirectoryNames = @(
    '.dart_tool',
    '.gradle',
    '.kotlin',
    '.idea',
    'build',
    'generated',
    'ephemeral',
    'intermediates',
    'outputs',
    'cxx',
    'captures',
    'reports',
    'transforms',
    'tmp',
    'configuration-cache'
)
$excludedGeneratedFileNames = @(
    'local.properties',
    'GeneratedPluginRegistrant.java',
    'GeneratedPluginRegistrant.kt'
)
$sourceFiles = foreach ($sourceRoot in $sourceRoots) {
    $sourcePath = Join-Path $repoRoot $sourceRoot
    if (Test-Path -LiteralPath $sourcePath -PathType Container) {
        Get-ChildItem -LiteralPath $sourcePath -File -Recurse -Force | Where-Object {
            $relativePath = $_.FullName.Substring($repoRoot.Length + 1).Replace('\', '/')
            $lastSeparator = $relativePath.LastIndexOf('/')
            $directoryNames = if ($lastSeparator -ge 0) {
                $relativePath.Substring(0, $lastSeparator).Split('/')
            } else {
                @()
            }
            $hasGeneratedDirectory = @($directoryNames | Where-Object { $excludedSourceDirectoryNames -contains $_ }).Count -gt 0
            -not $hasGeneratedDirectory -and $excludedGeneratedFileNames -notcontains $_.Name
        }
    } elseif (Test-Path -LiteralPath $sourcePath -PathType Leaf) {
        Get-Item -LiteralPath $sourcePath
    } else {
        throw "Source manifest input is missing: $sourceRoot"
    }
}
$manifestLines = foreach ($file in ($sourceFiles | Sort-Object FullName -Unique)) {
    $relativePath = $file.FullName.Substring($repoRoot.Length + 1).Replace('\', '/')
    $fileHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$relativePath  $fileHash"
}
$manifestPath = Join-Path $runDir 'source-manifest.sha256'
[System.IO.File]::WriteAllLines($manifestPath, $manifestLines, [System.Text.UTF8Encoding]::new($false))
$actualManifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualManifestHash -ne $ExpectedSourceManifestHash.ToLowerInvariant()) {
    throw "Source manifest hash mismatch; expected $ExpectedSourceManifestHash, got $actualManifestHash. No device build was started."
}
"candidate_source_manifest_sha256=$actualManifestHash" | Set-Content -LiteralPath $runLog
"candidate=$actualManifestHash profile=$DeviceProfile scenario=$Scenario serial=$serial avd=$actualAvd" | Add-Content -LiteralPath $runLog
"device_preflight serial=$serial avd=$actualAvd boot_completed=$bootCompleted api_level=$apiLevel emulator_version=$emulatorVersion command_line=$emulatorCommandLine" | Add-Content -LiteralPath $runLog
"flutter=$flutter" | Add-Content -LiteralPath $runLog
"adb=$adb server_port=5041 build_sdk=$buildSdk runtime_sdk=$runtimeSdk" | Add-Content -LiteralPath $runLog

function Get-DescendantProcesses([int]$RootProcessId, [long]$RootCreationTicks) {
    $processes = @(Get-CimInstance Win32_Process)
    $knownDepths = @{ [string]$RootProcessId = 0 }
    $knownCreationTicks = @{ [string]$RootProcessId = $RootCreationTicks }
    $descendants = @()
    $changed = $true
    while ($changed) {
        $changed = $false
        foreach ($candidate in $processes) {
            $candidateId = [string]$candidate.ProcessId
            $parentId = [string]$candidate.ParentProcessId
            $candidateCreationTicks = ([datetime]$candidate.CreationDate).ToUniversalTime().Ticks
            if ($knownDepths.ContainsKey($parentId) -and
                -not $knownDepths.ContainsKey($candidateId) -and
                $candidateCreationTicks -ge [long]$knownCreationTicks[$parentId]) {
                $depth = [int]$knownDepths[$parentId] + 1
                $knownDepths[$candidateId] = $depth
                $knownCreationTicks[$candidateId] = $candidateCreationTicks
                $descendants += [pscustomobject]@{
                    ProcessId = [int]$candidate.ProcessId
                    Depth = $depth
                    Name = $candidate.Name
                    CommandLine = $candidate.CommandLine
                    CreationDate = [string]$candidate.CreationDate
                    CreationTicks = ([datetime]$candidate.CreationDate).ToUniversalTime().Ticks
                }
                $changed = $true
            }
        }
    }
    return @($descendants | Sort-Object Depth -Descending)
}

function Test-CreationTimeMatch([long]$LeftTicks, [long]$RightTicks) {
    return ([Math]::Abs($LeftTicks - $RightTicks) -le 10)
}

function Get-RootProcessFingerprint($RootProcess) {
    $RootProcess.Refresh()
    if ($RootProcess.HasExited) { throw 'Flutter launcher exited before its root fingerprint could be captured.' }
    $rootId = [int]$RootProcess.Id
    $rootStartTicks = $RootProcess.StartTime.ToUniversalTime().Ticks
    $rootSnapshot = @(Get-CimInstance Win32_Process -Filter "ProcessId=$rootId")
    if ($rootSnapshot.Count -ne 1 -or -not (Test-CreationTimeMatch $rootStartTicks (([datetime]$rootSnapshot[0].CreationDate).ToUniversalTime().Ticks))) {
        throw "Could not establish a stable launcher fingerprint for PID $rootId."
    }
    [pscustomobject]@{
        ProcessId = $rootId
        CreationTicks = ([datetime]$rootSnapshot[0].CreationDate).ToUniversalTime().Ticks
        CommandLine = [string]$rootSnapshot[0].CommandLine
    }
}

function Test-RootProcessFingerprint($RootProcess, $RootFingerprint) {
    try {
        $RootProcess.Refresh()
        if ($RootProcess.HasExited -or [int]$RootProcess.Id -ne [int]$RootFingerprint.ProcessId) { return $false }
        if (-not (Test-CreationTimeMatch $RootProcess.StartTime.ToUniversalTime().Ticks ([long]$RootFingerprint.CreationTicks))) { return $false }
        $snapshot = @(Get-CimInstance Win32_Process -Filter "ProcessId=$($RootFingerprint.ProcessId)")
        return ($snapshot.Count -eq 1 -and
            ([datetime]$snapshot[0].CreationDate).ToUniversalTime().Ticks -eq [long]$RootFingerprint.CreationTicks -and
            [string]$snapshot[0].CommandLine -eq [string]$RootFingerprint.CommandLine)
    } catch {
        return $false
    }
}

function Add-TrackedDescendantProcesses($RootProcess, $RootFingerprint, [hashtable]$TrackedProcesses) {
    if (-not (Test-RootProcessFingerprint $RootProcess $RootFingerprint)) { return }
    $observed = @(Get-DescendantProcesses ([int]$RootFingerprint.ProcessId) ([long]$RootFingerprint.CreationTicks))
    if (-not (Test-RootProcessFingerprint $RootProcess $RootFingerprint)) {
        "phase_process_observation_discarded root_pid=$($RootFingerprint.ProcessId) reason=root_exited_or_identity_changed" | Add-Content -LiteralPath $runLog
        return
    }
    foreach ($descendant in $observed) {
        $key = '{0}|{1}|{2}' -f $descendant.ProcessId, $descendant.CreationTicks, $descendant.CommandLine
        if (-not $TrackedProcesses.ContainsKey($key)) {
            $priorIdentity = @($TrackedProcesses.Values | Where-Object { [int]$_.ProcessId -eq [int]$descendant.ProcessId })
            if ($priorIdentity.Count -gt 0) {
                "phase_process_pid_reused root_pid=$($RootFingerprint.ProcessId) pid=$($descendant.ProcessId) prior_fingerprints=$($priorIdentity.Count) new_creation=$($descendant.CreationDate) new_cmd=$($descendant.CommandLine)" | Add-Content -LiteralPath $runLog
            }
            $TrackedProcesses[$key] = $descendant
            "phase_process_observed root_pid=$($RootFingerprint.ProcessId) pid=$($descendant.ProcessId) name=$($descendant.Name) creation=$($descendant.CreationDate) cmd=$($descendant.CommandLine)" | Add-Content -LiteralPath $runLog
        }
    }
}

function Get-PhaseCommandLineResiduals([string]$Phase, [long]$PhaseStartTicks = 0) {
    $scriptTokens = @(
        'integration_test/agent_task_longrun_android_test.dart',
        'integration_test\agent_task_longrun_android_test.dart'
    )
    $phaseToken = "E2E_AGENT_PHASE=$Phase"
    $processes = @(Get-CimInstance Win32_Process)
    return @($processes | Where-Object {
        $commandLine = [string]$_.CommandLine
        $createdTicks = ([datetime]$_.CreationDate).ToUniversalTime().Ticks
        $createdTicks -ge $PhaseStartTicks -and
        @($scriptTokens | Where-Object { $commandLine.IndexOf($_, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 }).Count -gt 0 -and
        $commandLine.IndexOf($phaseToken, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
    } | ForEach-Object {
        [pscustomobject]@{
            ProcessId = [int]$_.ProcessId
            Name = $_.Name
            CreationDate = [string]$_.CreationDate
            CommandLine = [string]$_.CommandLine
            HasRunToken = ([string]$_.CommandLine).IndexOf('E2E_ACCEPTANCE_RUN_TOKEN=', [System.StringComparison]::OrdinalIgnoreCase) -ge 0
        }
    })
}

function Stop-TrackedChildProcess($Tracked, [string]$Phase, [string]$Reason) {
    $childHandle = $null
    try {
        $childHandle = [System.Diagnostics.Process]::GetProcessById([int]$Tracked.ProcessId)
        $childHandle.Refresh()
        if ($childHandle.HasExited) { return 'exited' }
        $handleStartTicks = $childHandle.StartTime.ToUniversalTime().Ticks
        if (-not (Test-CreationTimeMatch $handleStartTicks ([long]$Tracked.CreationTicks))) {
            "phase_process_identity_changed phase=$Phase pid=$($Tracked.ProcessId) expected_creation_ticks=$($Tracked.CreationTicks) handle_creation_ticks=$handleStartTicks; not_killed=true" | Add-Content -LiteralPath $runLog
            return 'reused'
        }
        $liveSnapshot = @(Get-CimInstance Win32_Process -Filter "ProcessId=$($Tracked.ProcessId)")
        if ($liveSnapshot.Count -ne 1 -or
            ([datetime]$liveSnapshot[0].CreationDate).ToUniversalTime().Ticks -ne [long]$Tracked.CreationTicks -or
            [string]$liveSnapshot[0].CommandLine -ne [string]$Tracked.CommandLine) {
            "phase_process_identity_changed phase=$Phase pid=$($Tracked.ProcessId) expected_creation=$($Tracked.CreationDate) live_creation=$(if($liveSnapshot.Count -eq 1){$liveSnapshot[0].CreationDate}else{'missing'}) expected_cmd=$($Tracked.CommandLine); not_killed=true" | Add-Content -LiteralPath $runLog
            return 'mismatch'
        }
        "phase_process_cleanup phase=$Phase reason=$Reason pid=$($Tracked.ProcessId) name=$($Tracked.Name) cmd=$($Tracked.CommandLine)" | Add-Content -LiteralPath $runLog
        $childHandle.Kill()
        $childHandle.WaitForExit(5000) | Out-Null
        return 'killed'
    } catch [System.ArgumentException] {
        "phase_process_already_exited phase=$Phase pid=$($Tracked.ProcessId)" | Add-Content -LiteralPath $runLog
        return 'exited'
    } finally {
        if ($null -ne $childHandle) { $childHandle.Dispose() }
    }
}

function Test-TrackedChildAlive($Tracked) {
    $childHandle = $null
    try {
        $childHandle = [System.Diagnostics.Process]::GetProcessById([int]$Tracked.ProcessId)
        $childHandle.Refresh()
        if ($childHandle.HasExited) { return $false }
        if (-not (Test-CreationTimeMatch $childHandle.StartTime.ToUniversalTime().Ticks ([long]$Tracked.CreationTicks))) { return $false }
        $liveSnapshot = @(Get-CimInstance Win32_Process -Filter "ProcessId=$($Tracked.ProcessId)")
        return ($liveSnapshot.Count -eq 1 -and
            ([datetime]$liveSnapshot[0].CreationDate).ToUniversalTime().Ticks -eq [long]$Tracked.CreationTicks -and
            [string]$liveSnapshot[0].CommandLine -eq [string]$Tracked.CommandLine)
    } catch {
        return $false
    } finally {
        if ($null -ne $childHandle) { $childHandle.Dispose() }
    }
}

function Stop-IntegrationProcessTree($RootProcess, $RootFingerprint, [string]$Phase, [string]$Reason, [hashtable]$TrackedProcesses, [long]$PhaseStartTicks, [string]$RunToken) {
    $rootId = [int]$RootProcess.Id
    if ($null -ne $RootFingerprint) { Add-TrackedDescendantProcesses $RootProcess $RootFingerprint $TrackedProcesses }
    foreach ($tracked in @($TrackedProcesses.Values)) {
        $null = Stop-TrackedChildProcess $tracked $Phase $Reason
    }
    try {
        $RootProcess.Refresh()
        if (-not $RootProcess.HasExited) {
            "phase_process_cleanup phase=$Phase reason=$Reason pid=$rootId name=launcher" | Add-Content -LiteralPath $runLog
            $RootProcess.Kill()
            $RootProcess.WaitForExit(5000) | Out-Null
        }
    } catch {
        "phase_process_cleanup_error phase=$Phase pid=$rootId error=$($_.Exception.Message)" | Add-Content -LiteralPath $runLog
    }
    if ($null -eq $RootFingerprint) {
        try {
            $unverifiedResiduals = @(Get-PhaseCommandLineResiduals $Phase $PhaseStartTicks)
            foreach ($residual in $unverifiedResiduals) {
                "phase_process_cleanup_unverified_residual phase=$Phase run_token=$RunToken pid=$($residual.ProcessId) name=$($residual.Name) creation=$($residual.CreationDate) run_token_present=$($residual.HasRunToken) cmd=$($residual.CommandLine); not_killed=true" | Add-Content -LiteralPath $runLog
            }
            "phase_process_cleanup_unverified phase=$Phase root_pid=$rootId reason=root_fingerprint_unavailable descendants_not_enumerated=true exact_run_residuals=$($unverifiedResiduals.Count)" | Add-Content -LiteralPath $runLog
        } catch {
            "phase_process_cleanup_unverified phase=$Phase root_pid=$rootId reason=root_fingerprint_unavailable residual_scan_error=$($_.Exception.Message); not_killed=true" | Add-Content -LiteralPath $runLog
        }
        throw "Cannot safely verify child-process cleanup for phase $Phase because the launcher fingerprint was unavailable."
    }
    $remaining = @()
    $cleanupDeadline = [DateTime]::UtcNow.AddSeconds(10)
    do {
        if ($null -ne $RootFingerprint -and (Test-RootProcessFingerprint $RootProcess $RootFingerprint)) {
            Add-TrackedDescendantProcesses $RootProcess $RootFingerprint $TrackedProcesses
        }
        $remaining = @()
        foreach ($tracked in @($TrackedProcesses.Values)) {
            if (Test-TrackedChildAlive $tracked) {
                $remaining += $tracked
                $null = Stop-TrackedChildProcess $tracked $Phase $Reason
            }
        }
        try {
            $RootProcess.Refresh()
            if (-not $RootProcess.HasExited) { $remaining += [pscustomobject]@{ ProcessId = $rootId; Depth = 0; Name = 'launcher'; CommandLine = if ($null -ne $RootFingerprint) { $RootFingerprint.CommandLine } else { 'start-process-handle' } } }
        } catch { }
        $remaining = @($remaining | Sort-Object ProcessId -Unique)
        if ($remaining.Count -gt 0) { Start-Sleep -Milliseconds 250 }
    } while ($remaining.Count -gt 0 -and [DateTime]::UtcNow -lt $cleanupDeadline)
    if ($remaining.Count -gt 0) {
        foreach ($left in $remaining) {
            "phase_process_cleanup_remaining phase=$Phase pid=$($left.ProcessId) name=$($left.Name) cmd=$($left.CommandLine)" | Add-Content -LiteralPath $runLog
        }
        throw "Could not terminate every observed process launched for phase $Phase (root PID $rootId)."
    }
    $commandLineResiduals = @(Get-PhaseCommandLineResiduals $Phase $PhaseStartTicks)
    if ($commandLineResiduals.Count -gt 0) {
        foreach ($residual in $commandLineResiduals) {
            "phase_process_residual_untracked phase=$Phase run_token=$RunToken pid=$($residual.ProcessId) name=$($residual.Name) creation=$($residual.CreationDate) run_token_present=$($residual.HasRunToken) cmd=$($residual.CommandLine); not_killed=true" | Add-Content -LiteralPath $runLog
        }
        throw "Exact phase command-line residual scan found $($commandLineResiduals.Count) process(es) that cannot be safely tied to a tracked handle for phase $Phase."
    }
    "phase_process_cleanup_verified phase=$Phase root_pid=$rootId observed_descendants=$($TrackedProcesses.Count) live=0" | Add-Content -LiteralPath $runLog
}

function Test-OutputContainsMarker(
    [AllowNull()][string]$Output,
    [AllowEmptyString()][string]$Marker
) {
    if ([string]::IsNullOrEmpty($Output) -or [string]::IsNullOrEmpty($Marker)) {
        return $false
    }
    return $Output.Contains($Marker)
}

function ConvertFrom-LongrunFailureArchiveOutput([string[]]$Lines) {
    $beginLines = @($Lines | Where-Object { $_ -match '^AGENT_LONGRUN_FAILURE_ARCHIVE_BEGIN\|' })
    $endLines = @($Lines | Where-Object { $_ -match '^AGENT_LONGRUN_FAILURE_ARCHIVE_END\|' })
    if ($beginLines.Count -ne 1 -or $endLines.Count -ne 1) {
        throw "Expected exactly one longrun archive begin/end marker pair; found begin=$($beginLines.Count) end=$($endLines.Count)."
    }
    $beginMatch = [regex]::Match($beginLines[0], '^AGENT_LONGRUN_FAILURE_ARCHIVE_BEGIN\|v1\|([0-9a-f]{64})\|(\d+)\|(\d+)$')
    $endMatch = [regex]::Match($endLines[0], '^AGENT_LONGRUN_FAILURE_ARCHIVE_END\|v1\|([0-9a-f]{64})$')
    if (-not $beginMatch.Success -or -not $endMatch.Success -or $beginMatch.Groups[1].Value -cne $endMatch.Groups[1].Value) {
        throw 'Longrun failure archive begin/end metadata is malformed or inconsistent.'
    }
    $expectedHash = $beginMatch.Groups[1].Value
    $expectedBytes = [long]$beginMatch.Groups[2].Value
    $expectedChunkCount = [int]$beginMatch.Groups[3].Value
    if ($expectedBytes -le 0 -or $expectedBytes -gt 67108864 -or $expectedChunkCount -le 0) {
        throw "Longrun failure archive declared invalid size/chunk count: bytes=$expectedBytes chunks=$expectedChunkCount."
    }
    $chunkMatches = @{}
    foreach ($line in $Lines) {
        if ($line -notmatch '^AGENT_LONGRUN_FAILURE_ARCHIVE_CHUNK\|') { continue }
        $chunkMatch = [regex]::Match($line, '^AGENT_LONGRUN_FAILURE_ARCHIVE_CHUNK\|(\d+)\|([A-Za-z0-9+/=]+)$')
        if (-not $chunkMatch.Success) { throw 'Longrun failure archive contains a malformed chunk marker.' }
        $index = [int]$chunkMatch.Groups[1].Value
        if ($index -lt 1 -or $index -gt $expectedChunkCount -or $chunkMatches.ContainsKey($index)) {
            throw "Longrun failure archive has an invalid or duplicate chunk index $index."
        }
        $chunkMatches[$index] = $chunkMatch.Groups[2].Value
    }
    if ($chunkMatches.Count -ne $expectedChunkCount) {
        throw "Longrun failure archive is incomplete: expected $expectedChunkCount chunks, found $($chunkMatches.Count)."
    }
    $encoded = for ($index = 1; $index -le $expectedChunkCount; $index++) {
        if (-not $chunkMatches.ContainsKey($index)) { throw "Longrun failure archive is missing chunk $index." }
        $chunkMatches[$index]
    }
    try { $archiveBytes = [Convert]::FromBase64String(($encoded -join '')) }
    catch { throw "Longrun failure archive base64 is invalid: $($_.Exception.Message)" }
    if ($archiveBytes.Length -ne $expectedBytes) {
        throw "Longrun failure archive length mismatch: expected $expectedBytes, decoded $($archiveBytes.Length)."
    }
    $actualHash = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($archiveBytes)).ToLowerInvariant()
    if ($actualHash -cne $expectedHash) { throw "Longrun failure archive SHA-256 mismatch: expected $expectedHash, got $actualHash." }
    $memory = [System.IO.MemoryStream]::new($archiveBytes, $false)
    $zip = $null
    try {
        $zip = [System.IO.Compression.ZipArchive]::new($memory, [System.IO.Compression.ZipArchiveMode]::Read, $false)
        $entryNames = @($zip.Entries | ForEach-Object { $_.FullName })
        foreach ($requiredEntry in @('failure-metadata.json', 'agent-events.jsonl', 'vault/.local/agent-task-checkpoint.json', 'index.sqlite3')) {
            if ($requiredEntry -notin $entryNames) { throw "Longrun failure archive is missing required evidence entry '$requiredEntry'." }
        }
        $metadataEntry = $zip.GetEntry('failure-metadata.json')
        $reader = [System.IO.StreamReader]::new($metadataEntry.Open())
        try { $metadata = $reader.ReadToEnd() | ConvertFrom-Json -ErrorAction Stop }
        finally { $reader.Dispose() }
        if ($metadata.schema_version -ne 1 -or
            $metadata.phase -ne 'longrun' -or
            $metadata.capture_stage -ne 'test_body_before_harness_teardown' -or
            $metadata.captured_before_harness_close -ne $true -or
            $metadata.snapshot_consistent -isnot [bool] -or
            [string]::IsNullOrWhiteSpace([string]$metadata.conversation_id)) {
            throw 'Longrun failure metadata is missing its schema, phase, pre-teardown capture proof, consistency flag, or conversation ID.'
        }
        $quiescence = $metadata.quiescence
        if ($null -eq $quiescence -or
            $quiescence.pause_settled -isnot [bool] -or
            $quiescence.pause_attempted -isnot [bool] -or
            $quiescence.pause_source_settled -isnot [bool] -or
            $quiescence.pause_checkpoint_settled -isnot [bool] -or
            $quiescence.generation_stopped -isnot [bool] -or
            $quiescence.business_turn_settled -isnot [bool] -or
            $quiescence.conversation_turns_stable -isnot [bool] -or
            $quiescence.table_refresh_settled -isnot [bool] -or
            $quiescence.background_status_refreshed -isnot [bool] -or
            $quiescence.checkpoint_loaded -isnot [bool] -or
            $quiescence.checkpoint_file_present -isnot [bool] -or
            $quiescence.index_database_file_present -isnot [bool]) {
            throw 'Longrun failure metadata has incomplete quiescence status fields.'
        }
        if ($metadata.snapshot_consistent -and
            (-not $quiescence.pause_settled -or
             -not $quiescence.pause_source_settled -or
             -not $quiescence.pause_checkpoint_settled -or
             -not $quiescence.generation_stopped -or
             -not $quiescence.business_turn_settled -or
             -not $quiescence.conversation_turns_stable -or
             -not $quiescence.table_refresh_settled -or
             -not $quiescence.background_status_refreshed -or
             -not $quiescence.checkpoint_loaded -or
             -not $quiescence.checkpoint_file_present -or
             -not $quiescence.index_database_file_present -or
             [string]::IsNullOrWhiteSpace([string]$metadata.longrun_initial_task_id) -or
             [string]::IsNullOrWhiteSpace([string]$metadata.longrun_initial_assistant_message_id) -or
             [string]::IsNullOrWhiteSpace([string]$quiescence.longrun_conversation_id) -or
             [string]::IsNullOrWhiteSpace([string]$quiescence.pause_target_task_id) -or
             [string]::IsNullOrWhiteSpace([string]$quiescence.pause_target_assistant_message_id) -or
             $quiescence.longrun_conversation_id -ne $metadata.conversation_id -or
             $quiescence.longrun_initial_task_id -ne $metadata.longrun_initial_task_id -or
             $quiescence.longrun_initial_assistant_message_id -ne $metadata.longrun_initial_assistant_message_id -or
             $quiescence.pause_target_task_id -ne $metadata.longrun_initial_task_id -or
             $quiescence.pause_target_assistant_message_id -ne $metadata.longrun_initial_assistant_message_id -or
             ($null -ne $quiescence.background_task_id -and $quiescence.background_task_id -ne $metadata.longrun_initial_assistant_message_id) -or
             $quiescence.background_state -eq 'running')) {
            throw 'Longrun archive claims a consistent snapshot despite an unsettled generation/turn/table refresh.'
        }
        if ($metadata.checkpoint_file_present -ne $true -or
            $metadata.event_file_present -ne $true -or
            $metadata.index_database_file_present -ne $true) {
            throw 'Longrun failure archive did not capture the checkpoint, fixture event log, and index/write-operation database.'
        }
        if ($null -eq $metadata.fixture -or
            -not ($metadata.fixture.PSObject.Properties.Name -contains 'last_write_receipt_event')) {
            throw 'Longrun failure archive is missing the fixture receipt field (a null receipt is recorded explicitly).'
        }
        return [pscustomobject]@{
            Bytes = $archiveBytes
            Sha256 = $actualHash
            Length = $archiveBytes.Length
            ChunkCount = $expectedChunkCount
            EntryNames = $entryNames
            ConversationId = [string]$metadata.conversation_id
            Metadata = $metadata
        }
    } finally {
        if ($null -ne $zip) { $zip.Dispose() }
        $memory.Dispose()
    }
}

function Export-LongrunFailureArchiveFromOutput([string]$StdoutPath) {
    if (-not (Test-Path -LiteralPath $StdoutPath -PathType Leaf)) {
        throw "Longrun stdout is missing; cannot export failure evidence: $StdoutPath"
    }
    $lines = @(Get-Content -LiteralPath $StdoutPath)
    $decoded = ConvertFrom-LongrunFailureArchiveOutput $lines
    $evidenceDirectory = Join-Path $runDir 'failure-evidence'
    New-Item -ItemType Directory -Path $evidenceDirectory -Force | Out-Null
    $archivePath = Join-Path $evidenceDirectory 'longrun-synthetic-profile.zip'
    [System.IO.File]::WriteAllBytes($archivePath, $decoded.Bytes)
    $writtenHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($writtenHash -cne $decoded.Sha256) { throw "Host failure archive readback hash mismatch: expected $($decoded.Sha256), got $writtenHash." }
    $record = [pscustomobject]@{
        status = 'exported'
        archive = $archivePath
        archive_sha256 = $decoded.Sha256
        archive_bytes = $decoded.Length
        chunk_count = $decoded.ChunkCount
        conversation_id = $decoded.ConversationId
        snapshot_consistent = [bool]$decoded.Metadata.snapshot_consistent
        quiescence = $decoded.Metadata.quiescence
        entry_names = $decoded.EntryNames
        exported_before_host_cleanup = $true
    }
    $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $evidenceDirectory 'longrun-archive-export.json') -Encoding utf8
    "longrun_failure_archive_export=success sha256=$($decoded.Sha256) bytes=$($decoded.Length) chunks=$($decoded.ChunkCount) conversation=$($decoded.ConversationId) snapshot_consistent=$($decoded.Metadata.snapshot_consistent)" | Add-Content -LiteralPath $runLog
    return $true
}

function Export-LongrunFallbackSnapshot([string]$DeviceProfileName) {
    $profileRoot = "files/secretary-agent-acceptance/$DeviceProfileName"
    $evidenceDirectory = Join-Path $runDir 'failure-evidence'
    New-Item -ItemType Directory -Path $evidenceDirectory -Force | Out-Null
    $saved = @()
    foreach ($relativePath in @('agent-events.jsonl', 'vault/.local/agent-task-checkpoint.json')) {
        $devicePath = "$profileRoot/$relativePath"
        $safeName = $relativePath.Replace('/', '_')
        $hostPath = Join-Path $evidenceDirectory $safeName
        try {
            $outputLength = Copy-AdbExecOutRunAsFile $adb $serial $packageName $devicePath $hostPath
            $firstLine = Get-Content -LiteralPath $hostPath -TotalCount 1 -ErrorAction Stop
            if ($outputLength -le 0 -or $firstLine -match '^run-as: unknown package:') {
                Remove-Item -LiteralPath $hostPath -Force -ErrorAction SilentlyContinue
                throw "Device package data was unavailable for $devicePath."
            }
            $saved += [pscustomobject]@{
                device_path = $devicePath
                host_path = $hostPath
                bytes = (Get-Item -LiteralPath $hostPath).Length
                sha256 = (Get-FileHash -LiteralPath $hostPath -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        } catch {
            "longrun_fallback_snapshot_file=failed path=$devicePath error=$($_.Exception.Message)" | Add-Content -LiteralPath $runLog
        }
    }
    $diagnosticFile = Join-Path $evidenceDirectory 'final-stream-diagnostic.json'
    $stdoutPath = Join-Path $runDir 'longrun.stdout.log'
    if (Test-Path -LiteralPath $stdoutPath -PathType Leaf) {
        $diagnosticLine = Get-Content -LiteralPath $stdoutPath | Where-Object { $_ -match '^AGENT_LONGRUN_FINAL_STREAM_DIAGNOSTIC\|' } | Select-Object -Last 1
        if ($diagnosticLine) {
            $json = $diagnosticLine.Substring('AGENT_LONGRUN_FINAL_STREAM_DIAGNOSTIC|'.Length)
            $diagnostic = $json | ConvertFrom-Json -ErrorAction Stop
            [System.IO.File]::WriteAllText($diagnosticFile, ($diagnostic | ConvertTo-Json -Depth 10), [System.Text.UTF8Encoding]::new($false))
            $saved += [pscustomobject]@{
                device_path = 'longrun.stdout.log:AGENT_LONGRUN_FINAL_STREAM_DIAGNOSTIC'
                host_path = $diagnosticFile
                bytes = (Get-Item -LiteralPath $diagnosticFile).Length
                sha256 = (Get-FileHash -LiteralPath $diagnosticFile -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        }
    }
    $record = [pscustomobject]@{ status = if ($saved.Count -gt 0) { 'partial' } else { 'failed' }; files = $saved }
    $record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $evidenceDirectory 'longrun-fallback-snapshot.json') -Encoding utf8
    "longrun_fallback_snapshot_saved=$($saved.Count) directory=$evidenceDirectory" | Add-Content -LiteralPath $runLog
    return ($saved.Count -gt 0)
}

function Invoke-IntegrationPhase(
    [string]$Phase,
    [int]$Seconds = 900,
    [int]$HostTimeoutMinutes = 6,
    [int]$StartupTimeoutMinutes = 8,
    [string]$BusinessStartMarker = 'AGENT_TEST_READY|',
    [string]$ReadyMarker = '',
    [scriptblock]$OnReady = {},
    [string[]]$AdditionalReadyMarkers = @(),
    [scriptblock]$OnAdditionalReady = {},
    [scriptblock]$OnRunningPoll = $null,
    [int]$RunningPollIntervalMilliseconds = 1000,
    [scriptblock]$OnFailureCapture = $null,
    [switch]$AllowExpectedDriverDisconnect
) {
    if ($HostTimeoutMinutes -lt 1 -or $HostTimeoutMinutes -gt 20) {
        throw 'Integration phase host timeout must be between 1 and 20 minutes.'
    }
    if ($StartupTimeoutMinutes -lt 1 -or $StartupTimeoutMinutes -gt 15) {
        throw 'Integration startup/build timeout must be between 1 and 15 minutes.'
    }
    if ($RunningPollIntervalMilliseconds -lt 250) {
        throw 'Running poll interval must be at least 250 milliseconds.'
    }
    $stdout = Join-Path $runDir "$Phase.stdout.log"
    $stderr = Join-Path $runDir "$Phase.stderr.log"
    $arguments = @(
        'test',
        'integration_test/agent_task_longrun_android_test.dart',
        '-d', $serial,
        '--no-pub',
        "--dart-define=E2E_AGENT_PHASE=$Phase",
        "--dart-define=E2E_ACCEPTANCE_RUN_TOKEN=$([guid]::NewGuid().ToString('N'))",
        "--dart-define=E2E_DEVICE_PROFILE=$DeviceProfile",
        "--dart-define=E2E_DURATION_SECONDS=$Seconds"
    )
    "phase_start=$Phase at=$([DateTime]::UtcNow.ToString('o'))" | Add-Content -LiteralPath $runLog
    $runTokenArgument = @($arguments | Where-Object { $_ -like '--dart-define=E2E_ACCEPTANCE_RUN_TOKEN=*' })[0]
    $runToken = $runTokenArgument.Substring('--dart-define=E2E_ACCEPTANCE_RUN_TOKEN='.Length)
    try {
        $stalePhaseProcesses = @(Get-PhaseCommandLineResiduals $Phase 0)
    } catch {
        "phase_preflight_scan_error=$Phase message=$($_.Exception.Message); failing_closed=true" | Add-Content -LiteralPath $runLog
        throw
    }
    if ($stalePhaseProcesses.Count -gt 0) {
        foreach ($stale in $stalePhaseProcesses) {
            "phase_preflight_stale_process phase=$Phase pid=$($stale.ProcessId) name=$($stale.Name) creation=$($stale.CreationDate) cmd=$($stale.CommandLine); not_killed=true" | Add-Content -LiteralPath $runLog
        }
        throw "A stale process matching the exact Flutter integration target and phase token exists for $Phase; refusing to start another phase."
    }
    $phaseStartTicks = [DateTime]::UtcNow.Ticks
    $process = Start-Process -FilePath $flutter -ArgumentList $arguments -WorkingDirectory $appRoot -RedirectStandardOutput $stdout -RedirectStandardError $stderr -WindowStyle Hidden -PassThru
    $trackedProcesses = @{}
    $rootFingerprint = $null
    $readyActionDone = $false
    $additionalReadyActionsDone = @{}
    $interruptionAt = $null
    $nextRunningPollAt = [DateTime]::UtcNow
    $phaseStartedAt = [DateTime]::UtcNow
    $startupDeadline = $phaseStartedAt.AddMinutes($StartupTimeoutMinutes)
    $businessDeadline = $null
    "phase_startup_timeout_minutes=$StartupTimeoutMinutes phase=$Phase business_timeout_minutes=$HostTimeoutMinutes business_start_marker=$BusinessStartMarker" | Add-Content -LiteralPath $runLog
    try {
        $rootFingerprint = Get-RootProcessFingerprint $process
        while (-not $process.HasExited -and [DateTime]::UtcNow -lt $(if ($null -ne $businessDeadline) { $businessDeadline } else { $startupDeadline })) {
            Start-Sleep -Milliseconds 250
            $process.Refresh()
            Add-TrackedDescendantProcesses $process $rootFingerprint $trackedProcesses
            $output = ''
            if (Test-Path -LiteralPath $stdout) {
                $capturedOutput = Get-Content -LiteralPath $stdout -Raw
                if ($null -ne $capturedOutput) { $output = [string]$capturedOutput }
            }
            if ($null -eq $businessDeadline -and (Test-OutputContainsMarker $output $BusinessStartMarker)) {
                $businessStartedAt = [DateTime]::UtcNow
                $businessDeadline = $businessStartedAt.AddMinutes($HostTimeoutMinutes)
                "phase_business_started=$Phase marker=$BusinessStartMarker at=$($businessStartedAt.ToString('o')) startup_elapsed_seconds=$([Math]::Round(($businessStartedAt - $phaseStartedAt).TotalSeconds, 3)) business_deadline=$($businessDeadline.ToString('o'))" | Add-Content -LiteralPath $runLog
            }
            if (-not $readyActionDone -and (Test-OutputContainsMarker $output $ReadyMarker)) {
                & $OnReady $output
                $readyActionDone = $true
                if ($AllowExpectedDriverDisconnect) { $interruptionAt = [DateTime]::UtcNow.AddSeconds(60) }
            }
            if ($readyActionDone -and $null -ne $OnRunningPoll -and [DateTime]::UtcNow -ge $nextRunningPollAt) {
                $pollOutput = if ($null -eq $output) { '' } else { [string]$output }
                & $OnRunningPoll $pollOutput
                $nextRunningPollAt = [DateTime]::UtcNow.AddMilliseconds($RunningPollIntervalMilliseconds)
            }
            foreach ($additionalMarker in $AdditionalReadyMarkers) {
                if (-not $additionalReadyActionsDone.ContainsKey($additionalMarker) -and (Test-OutputContainsMarker $output $additionalMarker)) {
                    & $OnAdditionalReady $additionalMarker $output
                    $additionalReadyActionsDone[$additionalMarker] = $true
                }
            }
            if ($AllowExpectedDriverDisconnect -and $readyActionDone -and $interruptionAt -and [DateTime]::UtcNow -ge $interruptionAt -and -not $process.HasExited) {
                Stop-IntegrationProcessTree $process $rootFingerprint $Phase 'expected_force_stop_driver_boundary' $trackedProcesses $phaseStartTicks $runToken
                'host_driver_stopped_after_force_stop_boundary; this is not an acceptance pass' | Add-Content -LiteralPath $runLog
            }
        }
        $process.Refresh()
        if (-not $process.HasExited) {
            if ($null -eq $businessDeadline) {
                throw "Integration phase $Phase exceeded its $StartupTimeoutMinutes minute startup/build/install timeout before business marker '$BusinessStartMarker'."
            }
            throw "Integration phase $Phase exceeded its $HostTimeoutMinutes minute business timeout after marker '$BusinessStartMarker'."
        }
    } catch {
        $script:integrationPhaseAbnormal = $true
        "phase_watcher_error=$Phase message=$($_.Exception.Message) at=$([DateTime]::UtcNow.ToString('o'))" | Add-Content -LiteralPath $runLog
        if ($null -ne $OnFailureCapture) {
            try {
                $captured = & $OnFailureCapture $_
                "phase_failure_evidence_capture=$Phase success=$([bool]$captured) stage=watcher_before_process_cleanup" | Add-Content -LiteralPath $runLog
            } catch {
                "phase_failure_evidence_capture=$Phase success=false error=$($_.Exception.Message) stage=watcher_before_process_cleanup" | Add-Content -LiteralPath $runLog
            }
        }
        Stop-IntegrationProcessTree $process $rootFingerprint $Phase 'unexpected_watcher_or_callback_failure' $trackedProcesses $phaseStartTicks $runToken
        throw
    }
    $process.Refresh()
    "phase_exit=$Phase code=$($process.ExitCode) at=$([DateTime]::UtcNow.ToString('o'))" | Add-Content -LiteralPath $runLog
    if ($null -ne $businessDeadline) {
        "phase_business_elapsed_seconds=$([Math]::Round(([DateTime]::UtcNow - $businessStartedAt).TotalSeconds, 3)) phase=$Phase marker=$BusinessStartMarker" | Add-Content -LiteralPath $runLog
    } else {
        "phase_business_marker_missing=true phase=$Phase marker=$BusinessStartMarker startup_elapsed_seconds=$([Math]::Round(([DateTime]::UtcNow - $phaseStartedAt).TotalSeconds, 3))" | Add-Content -LiteralPath $runLog
        $script:integrationPhaseAbnormal = $true
        throw "Integration phase $Phase exited before business-start marker '$BusinessStartMarker'."
    }
    Add-TrackedDescendantProcesses $process $rootFingerprint $trackedProcesses
    if ($AllowExpectedDriverDisconnect -and $readyActionDone) {
        Stop-IntegrationProcessTree $process $rootFingerprint $Phase 'expected_force_stop_driver_boundary_exit' $trackedProcesses $phaseStartTicks $runToken
        "phase_interrupted_by_design=$Phase code=$($process.ExitCode) ready_marker=$ReadyMarker" | Add-Content -LiteralPath $runLog
        return @{ interrupted = $true; stdout = $stdout; stderr = $stderr }
    }
    if ($process.ExitCode -ne 0) {
        $script:integrationPhaseAbnormal = $true
        if ($null -ne $OnFailureCapture) {
            try {
                $captured = & $OnFailureCapture ([System.Exception]::new("Flutter exit code $($process.ExitCode)"))
                "phase_failure_evidence_capture=$Phase success=$([bool]$captured) stage=nonzero_exit" | Add-Content -LiteralPath $runLog
            } catch {
                "phase_failure_evidence_capture=$Phase success=false error=$($_.Exception.Message) stage=nonzero_exit" | Add-Content -LiteralPath $runLog
            }
        }
        Stop-IntegrationProcessTree $process $rootFingerprint $Phase "flutter_exit_$($process.ExitCode)" $trackedProcesses $phaseStartTicks $runToken
        throw "Integration phase $Phase failed with exit code $($process.ExitCode). See $stdout and $stderr."
    }
    $missingAdditionalMarkers = @($AdditionalReadyMarkers | Where-Object { -not $additionalReadyActionsDone.ContainsKey($_) })
    if ($missingAdditionalMarkers.Count -gt 0) {
        $script:integrationPhaseAbnormal = $true
        if ($null -ne $OnFailureCapture) {
            try {
                $captured = & $OnFailureCapture ([System.Exception]::new("Required READY marker missing: $($missingAdditionalMarkers -join ', ')"))
                "phase_failure_evidence_capture=$Phase success=$([bool]$captured) stage=missing_marker" | Add-Content -LiteralPath $runLog
            } catch {
                "phase_failure_evidence_capture=$Phase success=false error=$($_.Exception.Message) stage=missing_marker" | Add-Content -LiteralPath $runLog
            }
        }
        Stop-IntegrationProcessTree $process $rootFingerprint $Phase 'required_ready_marker_missing' $trackedProcesses $phaseStartTicks $runToken
        throw "Integration phase $Phase exited without required READY markers: $($missingAdditionalMarkers -join ', ')."
    }
    Stop-IntegrationProcessTree $process $rootFingerprint $Phase 'normal_flutter_exit' $trackedProcesses $phaseStartTicks $runToken
    return @{ interrupted = $false; stdout = $stdout; stderr = $stderr }
}

function Ensure-AcceptancePackageInstalled {
    $packagePaths = @(& $adb -P 5041 -s $serial shell pm path $packageName 2>&1)
    if (@($packagePaths | Where-Object { $_ -match '^package:' }).Count -gt 0) { return }

    $apk = Join-Path $appRoot 'build\app\outputs\flutter-apk\app-debug.apk'
    $buildStdout = Join-Path $runDir 'permission-bootstrap-build.stdout.log'
    $buildStderr = Join-Path $runDir 'permission-bootstrap-build.stderr.log'
    $buildProcess = Start-Process -FilePath $flutter -ArgumentList @('build', 'apk', '--debug', '--no-pub') -WorkingDirectory $appRoot -RedirectStandardOutput $buildStdout -RedirectStandardError $buildStderr -WindowStyle Hidden -PassThru
    if (-not $buildProcess.WaitForExit(1200000)) {
        Stop-Process -Id $buildProcess.Id -Force
        throw 'Candidate APK bootstrap build exceeded 20 minutes.'
    }
    "permission_bootstrap_build_exit=$($buildProcess.ExitCode) stdout=$buildStdout stderr=$buildStderr" | Add-Content -LiteralPath $runLog
    if ($buildProcess.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $apk)) {
        throw 'Could not build the candidate APK needed to capture package permission defaults.'
    }
    $installOutput = & $adb -P 5041 -s $serial install -r $apk 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Could not install the candidate APK needed to capture package permission defaults: $installOutput"
    }
    "permission_bootstrap_install=success apk=$apk" | Add-Content -LiteralPath $runLog
}

$manageNotificationState = $Scenario -in @(
    'longrun',
    'force_stop_recovery',
    'activity_recreate',
    'service_interrupted',
    'service_timeout',
    'notification_denied'
)
if ($manageNotificationState) {
    Ensure-AcceptancePackageInstalled
    $notificationDeniedScenario = $Scenario -eq 'notification_denied'
    $permissionSnapshotBefore = if ($notificationDeniedScenario) { Get-NotificationPermissionSnapshot $adb $serial $packageName } else { $null }
    $permissionBefore = if ($notificationDeniedScenario) { $permissionSnapshotBefore.State } else { Get-NotificationPermissionState $adb $serial $packageName }
    $notificationAppOpBefore = Get-AppOpState $adb $serial $packageName 'POST_NOTIFICATION'
    if ($notificationAppOpBefore.PackageMode -ne 'default') {
        throw "POST_NOTIFICATION package baseline is '$($notificationAppOpBefore.PackageMode)'; acceptance only changes the runtime permission and will not write the package AppOp."
    }
    if (-not $notificationDeniedScenario) {
        $null = Get-NotificationPermissionAppOpExpectation $permissionBefore $notificationAppOpBefore 'granted'
    }
    $permissionTarget = if ($notificationDeniedScenario) { 'denied' } else { 'granted' }
    $permissionFlagsBefore = if ($notificationDeniedScenario) { "USER_SET=$($permissionSnapshotBefore.UserSet),USER_FIXED=$($permissionSnapshotBefore.UserFixed),raw=$($permissionSnapshotBefore.Flags -join '|')" } else { 'not-captured' }
    "scenario=$Scenario notification_permission_before=$permissionBefore notification_permission_flags_before=$permissionFlagsBefore notification_permission_target=$permissionTarget appop_uid_before=$($notificationAppOpBefore.UidMode) appop_package_before=$($notificationAppOpBefore.PackageMode) appop_effective_before=$(Get-AppOpEffectiveMode $notificationAppOpBefore) appop_raw_before=$($notificationAppOpBefore.Raw)" | Add-Content -LiteralPath $runLog
}

$outerCleanupFailures = [System.Collections.Generic.List[string]]::new()
$script:notificationDeniedForwardPort = $null
$script:integrationPhaseAbnormal = $false
try {
if ($manageNotificationState) {
    if ($notificationDeniedScenario) {
        'notification_denied_injection=deferred_until_test_ready install_complete=true appop_write=false' | Add-Content -LiteralPath $runLog
    } else {
        $permissionSetup = Set-NotificationPermissionState $adb $serial $packageName 'granted' $permissionBefore $notificationAppOpBefore
        "notification_permission_setup=complete permission=$($permissionSetup.Permission) appop_uid=$($permissionSetup.AppOp.UidMode) appop_package=$($permissionSetup.AppOp.PackageMode) appop_effective=$($permissionSetup.AppOp.EffectiveMode) appop_write=false" | Add-Content -LiteralPath $runLog
    }
}
if ($Scenario -eq 'secretary_matrix') {
    $caseIdList = @()
    if (-not [string]::IsNullOrWhiteSpace($CaseIds)) {
        $caseIdList = @($CaseIds.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if ($caseIdList.Count -eq 0 -or ($caseIdList | Select-Object -Unique).Count -ne $caseIdList.Count) {
            throw 'CaseIds must be a non-empty comma-separated list without duplicates.'
        }
        foreach ($caseId in $caseIdList) {
            if ($caseId -notmatch '^SEC-\d{3}$') { throw "Invalid secretary case ID: $caseId" }
        }
    }
    if ($caseIdList.Count -gt 0 -and $DeviceProfile -ne 'phone' -and ($caseIdList | Where-Object { $_ -in @('SEC-034', 'SEC-036', 'SEC-038') })) {
        throw 'SEC-034/036/038 are phone-only regressions.'
    }

    $arguments = @(
        'test',
        'integration_test/secretary_100_android_test.dart',
        '-d', $serial,
        '--no-pub',
        "--dart-define=E2E_PLATFORM=$DeviceProfile"
    )
    if ($caseIdList.Count -gt 0) {
        $arguments += "--dart-define=E2E_CASE_IDS=$($caseIdList -join ',')"
        $expectedCases = $caseIdList
    } else {
        $expectedCount = if ($DeviceProfile -eq 'phone') { 50 } else { 27 }
        $expectedCases = $null
    }
    $stdout = Join-Path $runDir 'secretary-matrix.stdout.log'
    $stderr = Join-Path $runDir 'secretary-matrix.stderr.log'
    "secretary_matrix_start=$([DateTime]::UtcNow.ToString('o')) selected=$($caseIdList -join ',')" | Add-Content -LiteralPath $runLog
    Push-Location $appRoot
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        # PowerShell surfaces native stderr as NativeCommandError records. Flutter
        # can emit Gradle/KGP warnings there while still returning exit code 0.
        # Keep both streams captured and let the real process status decide.
        $ErrorActionPreference = 'Continue'
        & $flutter @arguments 1> $stdout 2> $stderr
        $matrixExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
        Pop-Location
    }
    "secretary_matrix_exit=$matrixExitCode at=$([DateTime]::UtcNow.ToString('o'))" | Add-Content -LiteralPath $runLog
    if ($matrixExitCode -ne 0) {
        throw "Secretary matrix failed with exit code $matrixExitCode. See $stdout and $stderr."
    }
    $passedIds = @([regex]::Matches((Get-Content -LiteralPath $stdout -Raw), 'SEC_CASE_RESULT\|(SEC-\d{3})\|passed') | ForEach-Object { $_.Groups[1].Value })
    if ($null -ne $expectedCases) {
        $expectedCases = @($expectedCases | Sort-Object -Unique)
        $actualUnique = @($passedIds | Sort-Object -Unique)
        $missing = @($expectedCases | Where-Object { $_ -notin $actualUnique })
        $unexpected = @($actualUnique | Where-Object { $_ -notin $expectedCases })
        if ($missing.Count -gt 0 -or $unexpected.Count -gt 0 -or $passedIds.Count -ne $expectedCases.Count) {
            throw "Secretary case result mismatch. expected=$($expectedCases -join ',') passed=$($passedIds -join ',') missing=$($missing -join ',') unexpected=$($unexpected -join ',')."
        }
    } elseif ($passedIds.Count -ne $expectedCount -or @($passedIds | Sort-Object -Unique).Count -ne $expectedCount) {
        throw "Secretary matrix expected $expectedCount unique SEC_CASE_RESULT records, got $($passedIds.Count)."
    }
    foreach ($caseId in $passedIds) { "SEC_CASE_RESULT|$caseId|passed" | Add-Content -LiteralPath $runLog }
    "secretary_matrix_passed=$($passedIds.Count)" | Add-Content -LiteralPath $runLog
} elseif ($Scenario -eq 'force_stop_recovery') {
    $prepare = Invoke-IntegrationPhase -Phase 'prepare_force_stop' -Seconds $DurationSeconds -ReadyMarker 'AGENT_FORCE_STOP_READY|' -AllowExpectedDriverDisconnect -OnReady {
        param($output)
        & $adb -P 5041 -s $serial shell am force-stop $packageName | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'ADB force-stop failed.' }
        'force_stop_applied_after_persisted_ready_marker; prepare phase is interrupted, not passed' | Add-Content -LiteralPath $runLog
    }
    if (-not $prepare.interrupted) { throw 'Force-stop prepare did not reach the recorded recovery boundary.' }
    $deviceReadyDeadline = [DateTime]::UtcNow.AddSeconds(90)
    $deviceReady = $false
    do {
        $deviceLines = @(& $adb -P 5041 devices 2>&1)
        $deviceListExitCode = $LASTEXITCODE
        $connectedDevice = @($deviceLines | Where-Object { $_ -match "^$serial\s+device$" })
        if ($deviceListExitCode -eq 0 -and $connectedDevice.Count -eq 1) {
            $bootCompleted = (& $adb -P 5041 -s $serial shell getprop sys.boot_completed 2>&1).Trim()
            if ($LASTEXITCODE -eq 0 -and $bootCompleted -eq '1') {
                $deviceReady = $true
                break
            }
        }
        Start-Sleep -Milliseconds 1000
    } while ([DateTime]::UtcNow -lt $deviceReadyDeadline)
    if (-not $deviceReady) {
        throw "Device $serial did not return online and boot-complete within 90 seconds after force-stop."
    }
    "force_stop_recovery_device_ready serial=$serial boot_completed=$bootCompleted wait_seconds=$([math]::Round(90 - ($deviceReadyDeadline - [DateTime]::UtcNow).TotalSeconds, 1))" | Add-Content -LiteralPath $runLog
    $recovery = Invoke-IntegrationPhase -Phase 'recover_after_force_stop' -Seconds $DurationSeconds
} elseif ($Scenario -eq 'longrun') {
    $stayOnBefore = (Invoke-CheckedAdb -Label 'longrun_read_stay_on' -Arguments @('-P', '5041', '-s', $serial, 'shell', 'settings', 'get', 'global', 'stay_on_while_plugged_in')).Trim()
    if ($stayOnBefore -notmatch '^\d+$') { throw "Could not read stay_on_while_plugged_in before longrun: '$stayOnBefore'." }
    try {
        Invoke-CheckedAdb -Label 'longrun_enable_stay_on' -Arguments @('-P', '5041', '-s', $serial, 'shell', 'settings', 'put', 'global', 'stay_on_while_plugged_in', '3') | Out-Null
        Invoke-CheckedAdb -Label 'longrun_wake_before_startup' -Arguments @('-P', '5041', '-s', $serial, 'shell', 'input', 'keyevent', '224') | Out-Null
        Invoke-CheckedAdb -Label 'longrun_dismiss_keyguard_before_startup' -Arguments @('-P', '5041', '-s', $serial, 'shell', 'input', 'keyevent', '82') | Out-Null
        $awakeBeforeStartup = Get-DisplayLockSnapshot $serial
        if ($awakeBeforeStartup.ScreenOn -ne $true -or $awakeBeforeStartup.Interactive -ne $true -or $awakeBeforeStartup.KeyguardShowing) {
            throw "Longrun preflight could not wake display before Flutter startup: screen=$($awakeBeforeStartup.ScreenState), interactive_state=$($awakeBeforeStartup.InteractiveState)."
        }
        "longrun_stay_on_before=$stayOnBefore temporary_value=3 screen_on_before_startup=true" | Add-Content -LiteralPath $runLog
        $result = Invoke-IntegrationPhase -Phase 'longrun' -Seconds $DurationSeconds -HostTimeoutMinutes 20 -BusinessStartMarker 'AGENT_LONGTASK_STARTED|' -ReadyMarker 'AGENT_BACKGROUND_LOCK_READY|' -OnFailureCapture {
        param($failure)
        try {
            return [bool](Export-LongrunFailureArchiveFromOutput (Join-Path $runDir 'longrun.stdout.log'))
        } catch {
            "longrun_failure_archive_export=failed error=$($_.Exception.Message) original_failure=$($failure.Exception.Message)" | Add-Content -LiteralPath $runLog
            return [bool](Export-LongrunFallbackSnapshot $DeviceProfile)
        }
        } -OnReady {
        param($output)
        $beforeLock = Get-DisplayLockSnapshot $serial
        if ($beforeLock.ScreenOn -ne $true -or $beforeLock.Interactive -ne $true -or $beforeLock.KeyguardShowing) {
            throw "Longrun lock exercise must start with a screen-on, interactive, unlocked display; got screen=$($beforeLock.ScreenState), interactive_state=$($beforeLock.InteractiveState), interactive=$($beforeLock.Interactive), keyguard=$($beforeLock.KeyguardShowing)."
        }
        Invoke-CheckedAdb -Label 'longrun_home' -Arguments @('-P', '5041', '-s', $serial, 'shell', 'input', 'keyevent', '3') | Out-Null
        $background = Wait-ActivityPlacement $serial $packageName 'background'
        "longrun_background_before_lock=uid:$($background.UidState),nexusTop:$($background.TopResumedNexus),mainPaused:$($background.MainActivityPaused),hist:$([bool]$background.MainActivityRecord)" | Add-Content -LiteralPath $runLog

        Invoke-CheckedAdb -Label 'longrun_lock_screen' -Arguments @('-P', '5041', '-s', $serial, 'shell', 'input', 'keyevent', '26') | Out-Null
        $lockDeadline = [DateTime]::UtcNow.AddSeconds(5)
        $locked = $null
        do {
            $locked = Get-DisplayLockSnapshot $serial
            if ($locked.ScreenOn -eq $false -and $locked.Interactive -eq $false) { break }
            Start-Sleep -Milliseconds 250
        } while ([DateTime]::UtcNow -lt $lockDeadline)
        if ($null -eq $locked -or $locked.ScreenOn -ne $false -or $locked.Interactive -ne $false) {
            throw "Power key did not establish a verified screen-off state: screen=$($locked.ScreenState), interactive_state=$($locked.InteractiveState), interactive=$($locked.Interactive), keyguard=$($locked.KeyguardShowing)."
        }
        $lockedAt = [DateTime]::UtcNow
        while (([DateTime]::UtcNow - $lockedAt).TotalSeconds -lt 12) {
            Start-Sleep -Milliseconds 500
            $locked = Get-DisplayLockSnapshot $serial
            if ($locked.ScreenOn -ne $false -or $locked.Interactive -ne $false) {
                throw 'Display left the verified screen-off state during the 12-second background interval.'
            }
            $lockedPlacement = Get-ActivityPlacementSnapshot $serial $packageName
            if ([string]::IsNullOrWhiteSpace($lockedPlacement.MainActivityRecord) -or
                -not $lockedPlacement.MainActivityPaused -or
                $lockedPlacement.TopResumedApp) {
                throw "Target app was not demonstrably paused/backgrounded while locked: uid=$($lockedPlacement.UidState), paused=$($lockedPlacement.MainActivityPaused), appTop=$($lockedPlacement.TopResumedApp), hist=$([bool]$lockedPlacement.MainActivityRecord)."
            }
        }
        "longrun_screen_off_interval=verified_screen_off_12s_target_paused keyguard_showing=$($locked.KeyguardShowing)" | Add-Content -LiteralPath $runLog

        Invoke-CheckedAdb -Label 'longrun_wake_screen' -Arguments @('-P', '5041', '-s', $serial, 'shell', 'input', 'keyevent', '26') | Out-Null
        Invoke-CheckedAdb -Label 'longrun_dismiss_keyguard' -Arguments @('-P', '5041', '-s', $serial, 'shell', 'input', 'keyevent', '82') | Out-Null
        $wakeDeadline = [DateTime]::UtcNow.AddSeconds(5)
        $awake = $null
        do {
            $awake = Get-DisplayLockSnapshot $serial
            if ($awake.ScreenOn -eq $true -and $awake.Interactive -eq $true -and -not $awake.KeyguardShowing) { break }
            Start-Sleep -Milliseconds 250
        } while ([DateTime]::UtcNow -lt $wakeDeadline)
        if ($null -eq $awake -or $awake.ScreenOn -ne $true -or $awake.Interactive -ne $true -or $awake.KeyguardShowing) {
            throw "Unlock did not restore screen-on/interactive/unlocked state: screen=$($awake.ScreenState), interactive_state=$($awake.InteractiveState), interactive=$($awake.Interactive), keyguard=$($awake.KeyguardShowing)."
        }
        Invoke-CheckedAdb -Label 'longrun_reopen_app' -Arguments @('-P', '5041', '-s', $serial, 'shell', 'monkey', '-p', $packageName, '1') | Out-Null
        $foreground = Wait-ActivityPlacement $serial $packageName 'foreground'
        "longrun_foreground_after_unlock=uid:$($foreground.UidState),appTop:$($foreground.TopResumedApp),mainResumed:$($foreground.MainActivityResumed),hist:$([bool]$foreground.MainActivityRecord)" | Add-Content -LiteralPath $runLog
        'background_home_lock_unlock=verified' | Add-Content -LiteralPath $runLog
        }
    } finally {
        Invoke-CheckedAdb -Label 'longrun_restore_stay_on' -Arguments @('-P', '5041', '-s', $serial, 'shell', 'settings', 'put', 'global', 'stay_on_while_plugged_in', $stayOnBefore) | Out-Null
        "longrun_stay_on_restored=$stayOnBefore" | Add-Content -LiteralPath $runLog
    }
} elseif ($Scenario -eq 'activity_recreate') {
    $result = Invoke-IntegrationPhase -Phase 'activity_recreate' -Seconds $DurationSeconds -ReadyMarker 'AGENT_ACTIVITY_RECREATE_READY|' -OnReady {
        param($output)
        $broadcast = & $adb -P 5041 -s $serial shell am broadcast -n "$packageName/.DebugAgentBackgroundFaultReceiver" -a 'com.yuanfang.aitext.personal_ai_inbox.DEBUG_BACKGROUND_FAULT' --es fault_action recreate_activity 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Activity recreation injection failed: $broadcast" }
        "activity_recreation_injected=$broadcast" | Add-Content -LiteralPath $runLog
    }
} elseif ($Scenario -eq 'service_interrupted') {
    $result = Invoke-IntegrationPhase -Phase 'service_interrupted' -Seconds $DurationSeconds -ReadyMarker 'AGENT_SERVICE_STOP_READY|' -OnReady {
        param($output)
        $broadcast = & $adb -P 5041 -s $serial shell am broadcast -n "$packageName/.DebugAgentBackgroundFaultReceiver" -a 'com.yuanfang.aitext.personal_ai_inbox.DEBUG_BACKGROUND_FAULT' --es fault_action stop_service 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Foreground-service interruption injection failed: $broadcast" }
        "native_service_stop_injected=$broadcast" | Add-Content -LiteralPath $runLog
    }
} elseif ($Scenario -eq 'service_timeout') {
    $result = Invoke-IntegrationPhase -Phase 'service_timeout' -Seconds $DurationSeconds -ReadyMarker 'AGENT_SERVICE_STOP_READY|' -OnReady {
        param($output)
        $broadcast = & $adb -P 5041 -s $serial shell am broadcast -n "$packageName/.DebugAgentBackgroundFaultReceiver" -a 'com.yuanfang.aitext.personal_ai_inbox.DEBUG_BACKGROUND_FAULT' --es fault_action timeout 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Native dataSync timeout injection failed: $broadcast" }
        "native_data_sync_timeout_injected=$broadcast" | Add-Content -LiteralPath $runLog
    }
} elseif ($Scenario -eq 'service_restricted') {
    Ensure-AcceptancePackageInstalled
    $permissionBefore = Get-NotificationPermissionState $adb $serial $packageName
    $fgsAppOpBefore = Get-AppOpState $adb $serial $packageName 'START_FOREGROUND'
    $notificationAppOpBefore = Get-AppOpState $adb $serial $packageName 'POST_NOTIFICATION'
    $packageAppId = Get-PackageAppId $serial $packageName
    $restrictionMonitorState = New-ServiceRestrictionMonitorState
    $fgsEffectiveBefore = Get-AppOpEffectiveMode $fgsAppOpBefore
    if ($fgsAppOpBefore.UidMode -ne 'default') {
        throw "START_FOREGROUND UID baseline is '$($fgsAppOpBefore.UidMode)'; service restriction can only change the package-layer mode."
    }
    if ($notificationAppOpBefore.PackageMode -ne 'default') {
        throw "POST_NOTIFICATION package baseline is '$($notificationAppOpBefore.PackageMode)'; service restriction will only change the runtime permission."
    }
    $null = Get-NotificationPermissionAppOpExpectation $permissionBefore $notificationAppOpBefore 'granted'
    "notification_permission_before=$permissionBefore fgs_uid_before=$($fgsAppOpBefore.UidMode) fgs_package_before=$($fgsAppOpBefore.PackageMode) fgs_raw_before=$($fgsAppOpBefore.Raw) notification_uid_before=$($notificationAppOpBefore.UidMode) notification_package_before=$($notificationAppOpBefore.PackageMode)" | Add-Content -LiteralPath $runLog
    if ($fgsEffectiveBefore -in @('ignore', 'deny')) {
        throw "START_FOREGROUND baseline is already $fgsEffectiveBefore; refusing a service-restricted scenario that could not explicitly resume."
    }
    try {
        $permissionSetup = Set-NotificationPermissionState $adb $serial $packageName 'granted' $permissionBefore $notificationAppOpBefore
        "service_restricted_notification_permission_setup=complete permission=$($permissionSetup.Permission) uid=$($permissionSetup.AppOp.UidMode) package=$($permissionSetup.AppOp.PackageMode) effective=$($permissionSetup.AppOp.EffectiveMode) appop_write=false" | Add-Content -LiteralPath $runLog
        $null = Set-PackageAppOpState $adb $serial $packageName 'START_FOREGROUND' 'ignore' $fgsAppOpBefore
        $result = Invoke-IntegrationPhase -Phase 'service_restricted' -Seconds $DurationSeconds -ReadyMarker 'AGENT_SERVICE_RESTRICTED_BACKGROUND_READY|' -OnReady {
            param($output)
            & $adb -P 5041 -s $serial shell input keyevent 3 | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'Could not send HOME before starting the restricted task.' }
            $homeSentAt = [DateTime]::UtcNow
            $initialBackgroundState = Wait-ActivityPlacement $serial $packageName 'background'
            $backgroundState = Wait-BackgroundStartEligibility $serial $packageName $homeSentAt
            $injectedAppOp = Get-AppOpState $adb $serial $packageName 'START_FOREGROUND'
            $injectedAppOpMode = Get-AppOpEffectiveMode $injectedAppOp
            if ($injectedAppOpMode -ne 'ignore') { throw "Expected START_FOREGROUND=ignore before background task start; found '$injectedAppOpMode'." }
            $restrictionMonitorState.BackgroundUidState = $backgroundState.UidState
            "service_restricted_background_verified appId=$($backgroundState.AppId) uid_state=$($backgroundState.UidState) nexus_top=$($backgroundState.TopResumedNexus) main_paused=$($backgroundState.MainActivityPaused) hist_present=$([bool]$backgroundState.MainActivityRecord) injected_appop=$injectedAppOpMode post_home_settle_seconds=$($backgroundState.BackgroundElapsedSeconds)" | Add-Content -LiteralPath $runLog
            $ack = Invoke-LocalFixtureBarrier '/__acceptance/service_restricted_start' '{}' 'background-start'
            $restrictionMonitorState.StartAckAt = [DateTime]::UtcNow
            "service_restricted_background_start_barrier_ack=$ack appId=$($backgroundState.AppId) uid_state=$($backgroundState.UidState) initial_uid_state=$($initialBackgroundState.UidState) post_home_settle_seconds=$($backgroundState.BackgroundElapsedSeconds)" | Add-Content -LiteralPath $runLog
        } -AdditionalReadyMarkers @('AGENT_SERVICE_RESTRICTED_READY|', 'AGENT_SERVICE_RESTRICTED_RESULT|') -OnAdditionalReady {
            param($marker, $output)
            if ($marker -eq 'AGENT_SERVICE_RESTRICTED_RESULT|') {
                $readyIdentity = [pscustomobject]@{
                    AssistantId = $restrictionMonitorState.ReadyAssistantId
                    TaskId = $restrictionMonitorState.ReadyTaskId
                }
                $resultIdentity = Assert-ServiceRestrictedResultIdentity $readyIdentity $output
                "service_restricted_business_result_verified assistant_id=$($resultIdentity.AssistantId) generation_task_id=$($resultIdentity.TaskId)" | Add-Content -LiteralPath $runLog
                return
            }
            $readyIdentity = ConvertFrom-ServiceRestrictedReadyIdentity $output
            if (($restrictionMonitorState.ReadyAssistantId -and $restrictionMonitorState.ReadyAssistantId -ne $readyIdentity.AssistantId) -or
                ($restrictionMonitorState.ReadyTaskId -and $restrictionMonitorState.ReadyTaskId -ne $readyIdentity.TaskId)) {
                throw 'Service-restricted READY marker changed the assistant or durable task ID.'
            }
            $restrictionMonitorState.ReadyAssistantId = $readyIdentity.AssistantId
            $restrictionMonitorState.ReadyTaskId = $readyIdentity.TaskId
            $restrictionMonitorState.ReadyObservedAt = [DateTime]::UtcNow
            "service_restricted_ready_identity_saved assistant_id=$($readyIdentity.AssistantId) generation_task_id=$($readyIdentity.TaskId) denial_seen=$($restrictionMonitorState.DenialObserved) activity_thawed=$($restrictionMonitorState.ActivityThawed) resume_ack_sent=false" | Add-Content -LiteralPath $runLog
        } -OnRunningPoll {
            param($output)
            if ($restrictionMonitorState.ResumeAckAt) {
                if (Test-OutputContainsMarker $output 'AGENT_SERVICE_RESTRICTED_RESULT|') { return }
                if (([DateTime]::UtcNow - [DateTime]$restrictionMonitorState.ResumeAckAt).TotalSeconds -ge 120) {
                    throw 'Service-restricted task did not complete its verified business write within 120 seconds after explicit resume ACK.'
                }
                return
            }

            if (-not $restrictionMonitorState.DenialObserved) {
                $elapsed = ([DateTime]::UtcNow - [DateTime]$restrictionMonitorState.StartAckAt).TotalSeconds
                if ($elapsed -ge 60) { throw "Android FGS DENIED evidence was not observed within 60 seconds after start ACK (elapsed=${elapsed}s)." }
                $serviceDump = & $adb -P 5041 -s $serial shell dumpsys activity services $packageName 2>&1
                if ($LASTEXITCODE -ne 0) { throw 'Could not poll target service state while waiting for Android FGS DENIED evidence.' }
                $serviceFacts = Get-TargetServiceRestrictionFacts ($serviceDump -join "`n") $packageName $packageAppId
                if (-not $serviceFacts.DeniedBeforeStart) { return }
                $restrictionMonitorState.DenialObserved = $true
                $restrictionMonitorState.ReadyDeadline = [DateTime]::UtcNow.AddSeconds(60)
                "service_restricted_android_denied_observed elapsed_seconds=$([Math]::Round($elapsed,1)) target_record_present=$($serviceFacts.RecordExists) target_app_null=true start_foreground_count=0" | Add-Content -LiteralPath $runLog
                $launchOutput = & $adb -P 5041 -s $serial shell am start -W -n "$packageName/.MainActivity" -a android.intent.action.MAIN -c android.intent.category.LAUNCHER 2>&1
                $launchExit = $LASTEXITCODE
                "service_restricted_thaw_am_start_exit=$launchExit output=$($launchOutput -join ' ')" | Add-Content -LiteralPath $runLog
                if ($launchExit -ne 0) { throw "Android DENIED was observed, but launching MainActivity to thaw the app failed: $launchOutput" }
                $foregroundState = Wait-ActivityPlacement $serial $packageName 'foreground'
                $restrictionMonitorState.ActivityThawed = $true
                $restrictionMonitorState.ActivityThawedAt = [DateTime]::UtcNow
                "service_restricted_activity_thawed_after_denied appId=$($foregroundState.AppId) uid_state=$($foregroundState.UidState) main_resumed=$($foregroundState.MainActivityResumed) resume_ack_sent=false" | Add-Content -LiteralPath $runLog
                return
            }

            if (-not $restrictionMonitorState.ActivityThawed) {
                if ([DateTime]::UtcNow -ge [DateTime]$restrictionMonitorState.ReadyDeadline) {
                    throw 'Activity did not reach foreground placement within 60 seconds after Android DENIED; explicit resume was not acknowledged.'
                }
                return
            }
            if (-not $restrictionMonitorState.ReadyAssistantId -or -not $restrictionMonitorState.ReadyTaskId) {
                if ([DateTime]::UtcNow -ge [DateTime]$restrictionMonitorState.ReadyDeadline) {
                    throw 'Integration did not emit service-restricted READY within 60 seconds after Android DENIED and Activity thaw; explicit resume was not acknowledged.'
                }
                return
            }

            $assistantId = [string]$restrictionMonitorState.ReadyAssistantId
            $taskId = [string]$restrictionMonitorState.ReadyTaskId
            $foregroundState = Wait-ActivityPlacement $serial $packageName 'foreground'
            $serviceDump = & $adb -P 5041 -s $serial shell dumpsys activity services $packageName 2>&1
            if ($LASTEXITCODE -ne 0) { throw 'Could not inspect foreground services before resuming the restricted task.' }
            $serviceFacts = Get-TargetServiceRestrictionFacts ($serviceDump -join "`n") $packageName $packageAppId
            if ($serviceFacts.ForegroundServiceActive) { throw 'DataSyncForegroundService remained active after the restriction callback.' }
            $wakeLockDump = & $adb -P 5041 -s $serial shell dumpsys power 2>&1
            if ($LASTEXITCODE -ne 0) { throw 'Could not inspect wake locks before resuming the restricted task.' }
            $wakeLockText = $wakeLockDump -join "`n"
            $suspendBlockerOffset = $wakeLockText.IndexOf('Suspend Blockers:', [System.StringComparison]::Ordinal)
            $activeWakeLockSection = if ($suspendBlockerOffset -ge 0) {
                $wakeLockText.Substring(0, $suspendBlockerOffset)
            } else {
                $wakeLockText
            }
            if ($activeWakeLockSection -match '懒狗秘书:AgentTask') {
                throw 'AgentTask wake lock remained active after the restriction callback.'
            }
            $injectedAppOp = Get-AppOpState $adb $serial $packageName 'START_FOREGROUND'
            $injectedAppOpMode = Get-AppOpEffectiveMode $injectedAppOp
            if ($injectedAppOpMode -ne 'ignore') { throw "Expected START_FOREGROUND=ignore at restriction boundary; found '$injectedAppOpMode'." }
            "service_restricted_resume_foreground_verified task_id=$taskId appId=$($foregroundState.AppId) uid_state=$($foregroundState.UidState) main_resumed=$($foregroundState.MainActivityResumed)" | Add-Content -LiteralPath $runLog
            $null = Set-PackageAppOpState $adb $serial $packageName 'START_FOREGROUND' $fgsAppOpBefore.PackageMode $fgsAppOpBefore
            $restoredAppOp = Get-AppOpState $adb $serial $packageName 'START_FOREGROUND'
            if (-not (Test-AppOpStateEqual $restoredAppOp $fgsAppOpBefore)) { throw 'START_FOREGROUND package-layer mode did not restore before explicit task resume.' }
            "service_restricted_boundary task_id=$taskId fgs=absent agent_wakelock=absent injected_appop=ignore background_uid_state=$($restrictionMonitorState.BackgroundUidState) resumed_uid_state=$($foregroundState.UidState) restored_fgs_uid=$($restoredAppOp.UidMode) restored_fgs_package=$($restoredAppOp.PackageMode) restored_fgs_effective=$($restoredAppOp.EffectiveMode)" | Add-Content -LiteralPath $runLog
            $barrierBody = @{ assistant_message_id = $assistantId; task_id = $taskId } | ConvertTo-Json -Compress
            $ack = Invoke-LocalFixtureBarrier '/__acceptance/service_restricted_resume' $barrierBody 'explicit-resume'
            $restrictionMonitorState.ResumeAckAt = [DateTime]::UtcNow
            "service_restricted_resume_barrier_ack=$ack assistant_id=$assistantId generation_task_id=$taskId" | Add-Content -LiteralPath $runLog
        } -OnFailureCapture {
            param($failure)
            $restrictionMonitorState.FailureEvidenceAttempted = $true
            $restrictionMonitorState.FailureEvidenceExported = [bool](Export-ServiceRestrictedFailureEvidence $DeviceProfile $runId)
            return $restrictionMonitorState.FailureEvidenceExported
        }
    } catch {
        $phaseFailure = $_
        if (-not $restrictionMonitorState.FailureEvidenceAttempted) {
            $restrictionMonitorState.FailureEvidenceAttempted = $true
            $restrictionMonitorState.FailureEvidenceExported = [bool](Export-ServiceRestrictedFailureEvidence $DeviceProfile $runId)
        }
        $exported = $restrictionMonitorState.FailureEvidenceExported
        if (-not $exported) {
            "service_restricted_failure_evidence_export_required=failed; phase_failure=$($phaseFailure.Exception.Message)" | Add-Content -LiteralPath $runLog
            throw "Service-restricted phase failed and checkpoint/event/ledger evidence export failed. Original failure: $($phaseFailure.Exception.Message)"
        }
        throw
    } finally {
        $packagePath = @(& $adb -P 5041 -s $serial shell pm path $packageName 2>&1)
        $packagePathExitCode = $LASTEXITCODE
        $packageInstalled = @($packagePath | Where-Object { $_ -match '^package:' }).Count -gt 0
        if ($packageInstalled) {
            $restrictionCleanupFailures = [System.Collections.Generic.List[string]]::new()
            try {
                $null = Set-PackageAppOpState $adb $serial $packageName 'START_FOREGROUND' $fgsAppOpBefore.PackageMode $fgsAppOpBefore
            } catch {
                $restrictionCleanupFailures.Add("START_FOREGROUND package restore: $($_.Exception.Message)")
            }
            try {
                $permissionRestore = Set-NotificationPermissionState $adb $serial $packageName $permissionBefore $permissionBefore $notificationAppOpBefore
                $permissionAfter = $permissionRestore.Permission
                if ($permissionAfter -ne $permissionBefore) { throw "Expected permission $permissionBefore, got $permissionAfter." }
            } catch {
                $restrictionCleanupFailures.Add("POST_NOTIFICATIONS permission restore: $($_.Exception.Message)")
            }
            try {
                $appOpAfter = Get-AppOpState $adb $serial $packageName 'START_FOREGROUND'
                if (-not (Test-AppOpStateEqual $appOpAfter $fgsAppOpBefore)) {
                    throw "Expected captured UID/package/effective $($fgsAppOpBefore.UidMode)/$($fgsAppOpBefore.PackageMode)/$($fgsAppOpBefore.EffectiveMode), got $($appOpAfter.UidMode)/$($appOpAfter.PackageMode)/$($appOpAfter.EffectiveMode)."
                }
            } catch {
                $restrictionCleanupFailures.Add("START_FOREGROUND readback: $($_.Exception.Message)")
            }
            try {
                $notificationAppOpAfter = Get-AppOpState $adb $serial $packageName 'POST_NOTIFICATION'
                if (-not (Test-AppOpStateEqual $notificationAppOpAfter $notificationAppOpBefore)) {
                    throw "Expected captured UID/package/effective $($notificationAppOpBefore.UidMode)/$($notificationAppOpBefore.PackageMode)/$($notificationAppOpBefore.EffectiveMode), got $($notificationAppOpAfter.UidMode)/$($notificationAppOpAfter.PackageMode)/$($notificationAppOpAfter.EffectiveMode)."
                }
            } catch {
                $restrictionCleanupFailures.Add("POST_NOTIFICATION readback: $($_.Exception.Message)")
            }
            "post_phase_package=installed notification_permission_after=$(if ($permissionAfter) { $permissionAfter } else { 'unread' }) fgs_uid_after=$(if ($appOpAfter) { $appOpAfter.UidMode } else { 'unread' }) fgs_package_after=$(if ($appOpAfter) { $appOpAfter.PackageMode } else { 'unread' }) notification_uid_after=$(if ($notificationAppOpAfter) { $notificationAppOpAfter.UidMode } else { 'unread' }) notification_package_after=$(if ($notificationAppOpAfter) { $notificationAppOpAfter.PackageMode } else { 'unread' }) notification_effective_after=$(if ($notificationAppOpAfter) { $notificationAppOpAfter.EffectiveMode } else { 'unread' }) notification_appop_write=false cleanup_failures=$($restrictionCleanupFailures -join '; ')" | Add-Content -LiteralPath $runLog
            if ($restrictionCleanupFailures.Count -gt 0) {
                throw "Service-restricted permission/AppOp restoration failed: $($restrictionCleanupFailures -join '; ')."
            }
        } else {
            if ($packagePathExitCode -notin @(0, 1)) { throw "Could not determine package installation state during service-restricted cleanup (adb exit $packagePathExitCode): $($packagePath -join ' ')" }
            $packageDump = @(& $adb -P 5041 -s $serial shell dumpsys package $packageName 2>&1)
            $packageDumpExitCode = $LASTEXITCODE
            if ($packageDumpExitCode -ne 0) { throw "Could not verify package absence during service-restricted cleanup (adb exit $packageDumpExitCode): $($packageDump -join ' ')" }
            if (($packageDump -join "`n") -match "(?m)^Package \[$([regex]::Escape($packageName))\]") {
                throw 'pm path reported the package absent but dumpsys package still lists it.'
            }
            "post_phase_package=absent pm_path_exit=$packagePathExitCode pm_path=$($packagePath -join ' ') dumpsys_package=$($packageDump -join ' ') permission_appop_comparison=skipped_after_uninstall" | Add-Content -LiteralPath $runLog
        }
    }
} else {
    $script:notificationDeniedDialogCount = 0
    $result = Invoke-IntegrationPhase -Phase 'notification_denied' -Seconds $DurationSeconds -HostTimeoutMinutes 6 -ReadyMarker 'AGENT_NOTIFICATION_DENIED_PREPARE|' -OnReady {
        $packagePath = @(& $adb -P 5041 -s $serial shell pm path $packageName 2>&1)
        if ($LASTEXITCODE -ne 0 -or @($packagePath | Where-Object { $_ -match '^package:' }).Count -eq 0) {
            throw 'Notification denial barrier arrived before the candidate package was installed.'
        }
        $permissionDenied = Set-NotificationPermissionState $adb $serial $packageName 'denied' $permissionBefore $notificationAppOpBefore
        Set-NotificationPermissionFlag $adb $serial $packageName 'user-set' $true
        Set-NotificationPermissionFlag $adb $serial $packageName 'user-fixed' $true
        $permissionDeniedSnapshot = Get-NotificationPermissionSnapshot $adb $serial $packageName
        if ($permissionDeniedSnapshot.State -ne 'denied' -or -not $permissionDeniedSnapshot.UserSet -or -not $permissionDeniedSnapshot.UserFixed) {
            throw 'Could not establish deterministic user-fixed POST_NOTIFICATIONS denial after install.'
        }
        $notificationAppOpAtInjection = Get-AppOpState $adb $serial $packageName 'POST_NOTIFICATION'
        if (-not (Test-AppOpStateEqual $notificationAppOpAtInjection $permissionDenied.AppOp)) {
            throw 'POST_NOTIFICATION AppOp did not match the permission-only denial projection.'
        }
        "notification_denied_injection=permission_only state=$($permissionDeniedSnapshot.State) user_set=$($permissionDeniedSnapshot.UserSet) user_fixed=$($permissionDeniedSnapshot.UserFixed) appop_effective=$(Get-AppOpEffectiveMode $notificationAppOpAtInjection) appop_write=false stage=post_install_ready" | Add-Content -LiteralPath $runLog
        $forwardOutput = @(& $adb -P 5041 -s $serial forward tcp:0 tcp:47631 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "Could not forward the local permission barrier endpoint: $($forwardOutput -join ' ')" }
        $forwardMatches = @($forwardOutput | ForEach-Object { [regex]::Matches([string]$_, '(?<!\d)(\d{4,5})(?!\d)') } | ForEach-Object { $_ } | Where-Object { $_.Success })
        if ($forwardMatches.Count -ne 1) { throw "ADB forward did not return exactly one host port: $($forwardOutput -join ' ')" }
        $script:notificationDeniedForwardPort = [int]$forwardMatches[0].Groups[1].Value
        "notification_denied_barrier_forward=ready host_port=$script:notificationDeniedForwardPort device_port=47631" | Add-Content -LiteralPath $runLog
        Send-NotificationDeniedPermissionBarrierAck $script:notificationDeniedForwardPort
        'notification_denied_barrier_ack=sent permission_setup_complete=true' | Add-Content -LiteralPath $runLog
    } -OnRunningPoll {
        if (Test-NotificationPermissionDialogActive $adb $serial) {
            if ($script:notificationDeniedDialogCount -ge 1) {
                throw 'Android displayed another POST_NOTIFICATIONS permission dialog after explicit denial.'
            }
            $deniedDialog = Deny-NotificationPermissionDialog $adb $serial
            $script:notificationDeniedDialogCount++
            $permissionAfterDialog = Get-NotificationPermissionState $adb $serial $packageName
            if ($permissionAfterDialog -ne 'denied') {
                throw "Notification permission dialog denial did not leave the permission denied; found '$permissionAfterDialog'."
            }
            "notification_denied_dialog=dismissed_by_user_choice label=$($deniedDialog.Label) tap_x=$($deniedDialog.X) tap_y=$($deniedDialog.Y) permission=$permissionAfterDialog" | Add-Content -LiteralPath $runLog
        }
    } -RunningPollIntervalMilliseconds 500
}
} finally {
    if ($script:notificationDeniedForwardPort) {
        try {
            & $adb -P 5041 -s $serial forward --remove "tcp:$script:notificationDeniedForwardPort" | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "ADB could not remove notification barrier forward tcp:$script:notificationDeniedForwardPort (exit $LASTEXITCODE)." }
            "notification_denied_barrier_forward=removed host_port=$script:notificationDeniedForwardPort" | Add-Content -LiteralPath $runLog
        } catch {
            $outerCleanupFailures.Add("notification_barrier_forward_cleanup=$($_.Exception.Message)")
        }
        $script:notificationDeniedForwardPort = $null
    }
    if ($script:integrationPhaseAbnormal) {
        try {
            & $adb -P 5041 -s $serial shell am force-stop $packageName | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "ADB force-stop after abnormal integration phase failed (exit $LASTEXITCODE)." }
            'abnormal_phase_app_force_stop=success' | Add-Content -LiteralPath $runLog
        } catch {
            $outerCleanupFailures.Add("abnormal_phase_app_force_stop=$($_.Exception.Message)")
        }
    }
    if ($manageNotificationState) {
        try {
            $packagePath = @(& $adb -P 5041 -s $serial shell pm path $packageName 2>&1)
            $packageInstalled = @($packagePath | Where-Object { $_ -match '^package:' }).Count -gt 0
            if ($packageInstalled) {
                if ($notificationDeniedScenario) {
                    $permissionAfterSnapshot = Restore-NotificationPermissionSnapshot $adb $serial $packageName $permissionSnapshotBefore
                    $permissionAfter = $permissionAfterSnapshot.State
                    $notificationAppOpAfter = Get-AppOpState $adb $serial $packageName 'POST_NOTIFICATION'
                    $notificationAppOpEffectiveAfter = Get-AppOpEffectiveMode $notificationAppOpAfter
                    "post_phase_notification_denied_restore=permission_only state=$permissionAfter user_set=$($permissionAfterSnapshot.UserSet) user_fixed=$($permissionAfterSnapshot.UserFixed) appop_effective_before=$(Get-AppOpEffectiveMode $notificationAppOpBefore) appop_effective_after=$notificationAppOpEffectiveAfter appop_raw_after=$($notificationAppOpAfter.Raw)" | Add-Content -LiteralPath $runLog
                    if (-not (Test-AppOpStateEqual $notificationAppOpAfter $notificationAppOpBefore)) { throw 'POST_NOTIFICATION UID/package/effective modes did not return to the captured values after permission-only denial.' }
                } else {
                    $permissionRestore = Set-NotificationPermissionState $adb $serial $packageName $permissionBefore $permissionBefore $notificationAppOpBefore
                    $permissionAfter = $permissionRestore.Permission
                    $notificationAppOpAfter = Get-AppOpState $adb $serial $packageName 'POST_NOTIFICATION'
                    "post_phase_package=installed notification_permission_after=$permissionAfter appop_uid_after=$($notificationAppOpAfter.UidMode) appop_package_after=$($notificationAppOpAfter.PackageMode) appop_effective_after=$($notificationAppOpAfter.EffectiveMode) appop_write=false" | Add-Content -LiteralPath $runLog
                    if ($permissionAfter -ne $permissionBefore) { throw 'Notification permission did not return to its captured value.' }
                    if (-not (Test-AppOpStateEqual $notificationAppOpAfter $notificationAppOpBefore)) { throw 'POST_NOTIFICATION AppOp projection did not return to its captured permission-derived values.' }
                }
            } else {
                $packageDump = @(& $adb -P 5041 -s $serial shell dumpsys package $packageName 2>&1)
                if ($LASTEXITCODE -eq 0 -and (($packageDump -join "`n") -match "(?m)^Package \[$([regex]::Escape($packageName))\]")) {
                    throw 'pm path reported the package absent but dumpsys package still lists it.'
                }
                "post_phase_package=absent pm_path=$($packagePath -join ' ') dumpsys_package=$($packageDump -join ' ') permission_appop_comparison=skipped_after_uninstall" | Add-Content -LiteralPath $runLog
            }
        } catch {
            $outerCleanupFailures.Add("notification_cleanup=$($_.Exception.Message)")
        }
    }
    try {
        $serviceDump = & $adb -P 5041 -s $serial shell dumpsys activity services $packageName 2>&1
        if ($LASTEXITCODE -ne 0) { throw "dumpsys activity services failed in cleanup (exit $LASTEXITCODE)." }
        $activeService = $serviceDump | Select-String -Pattern 'DataSyncForegroundService'
        if ($activeService) {
            $outerCleanupFailures.Add('foreground service was active at phase termination')
            "post_test_service_lines=$activeService" | Add-Content -LiteralPath $runLog
            & $adb -P 5041 -s $serial shell am stopservice -n "$packageName/.DataSyncForegroundService" | Out-Null
            if ($LASTEXITCODE -ne 0) { $outerCleanupFailures.Add('foreground service cleanup stop command failed') }
            & $adb -P 5041 -s $serial shell am force-stop $packageName | Out-Null
            if ($LASTEXITCODE -ne 0) { $outerCleanupFailures.Add('package force-stop cleanup command failed') }
            $serviceDump = & $adb -P 5041 -s $serial shell dumpsys activity services $packageName 2>&1
            if ($LASTEXITCODE -ne 0) { throw "dumpsys activity services verification failed (exit $LASTEXITCODE)." }
            if ($serviceDump | Select-String -Pattern 'DataSyncForegroundService') {
                $outerCleanupFailures.Add('foreground service remained after cleanup')
            }
        } else {
            'post_test_service_lines=none' | Add-Content -LiteralPath $runLog
        }

        $wakeLockDump = & $adb -P 5041 -s $serial shell dumpsys power 2>&1
        if ($LASTEXITCODE -ne 0) { throw "dumpsys power failed in cleanup (exit $LASTEXITCODE)." }
        $wakeLockText = $wakeLockDump -join "`n"
        $suspendBlockerOffset = $wakeLockText.IndexOf('Suspend Blockers:', [System.StringComparison]::Ordinal)
        $activeWakeLockSection = if ($suspendBlockerOffset -ge 0) {
            $wakeLockText.Substring(0, $suspendBlockerOffset)
        } else {
            $wakeLockText
        }
        $activeWakeLock = if ($activeWakeLockSection -match '懒狗秘书:AgentTask') { $Matches[0] } else { $null }
        "post_test_wakelock_lines=$activeWakeLock current_wakelock_header=$($activeWakeLockSection | Select-String -Pattern '^Wake Locks: size=')" | Add-Content -LiteralPath $runLog
        if ($activeWakeLock) {
            $outerCleanupFailures.Add('AgentTask wakelock remained active after service cleanup')
            & $adb -P 5041 -s $serial shell am force-stop $packageName | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "Package force-stop for wake-lock cleanup failed (exit $LASTEXITCODE)." }
            $wakeLockDump = & $adb -P 5041 -s $serial shell dumpsys power 2>&1
            if ($LASTEXITCODE -ne 0) { throw "dumpsys power verification failed (exit $LASTEXITCODE)." }
            $wakeLockText = $wakeLockDump -join "`n"
            $suspendBlockerOffset = $wakeLockText.IndexOf('Suspend Blockers:', [System.StringComparison]::Ordinal)
            $activeWakeLockSection = if ($suspendBlockerOffset -ge 0) { $wakeLockText.Substring(0, $suspendBlockerOffset) } else { $wakeLockText }
            if ($activeWakeLockSection -match '懒狗秘书:AgentTask') { $outerCleanupFailures.Add('AgentTask wakelock remained after package force-stop') }
        }
    } catch {
        $outerCleanupFailures.Add("service_wakelock_cleanup=$($_.Exception.Message)")
    }
    if ($outerCleanupFailures.Count -gt 0) {
        $cleanupSummary = $outerCleanupFailures -join '; '
        "cleanup_failures=$cleanupSummary" | Add-Content -LiteralPath $runLog
    } else {
        'cleanup_failures=none' | Add-Content -LiteralPath $runLog
    }
}

if ($outerCleanupFailures.Count -gt 0) {
    throw "Android acceptance cleanup found: $($outerCleanupFailures -join '; '). See $runLog."
}

$apk = Join-Path $appRoot 'build\app\outputs\flutter-apk\app-debug.apk'
if (Test-Path -LiteralPath $apk) {
    $apkHash = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
    "apk=$apk sha256=$apkHash" | Add-Content -LiteralPath $runLog
}
"scenario_result=passed at=$([DateTime]::UtcNow.ToString('o'))" | Add-Content -LiteralPath $runLog
Write-Output "Android acceptance phase passed: $DeviceProfile / $Scenario. Evidence: $runDir"
