param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Candidate', 'Published')]
    [string]$Stage,

    [string]$SdkRoot = 'E:\DevTools\Android\Sdk',
    [string]$AvdHome = 'E:\DevTools\Android\.android\avd',
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$AvdName = 'aitext_v161_phone',
    [string]$OutputDir = 'E:\DevTools\Android\aitext-validation\phone-v1.6.1',
    [ValidateRange(1, [int]::MaxValue)]
    [int]$BootTimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$appRoot = Join-Path $repoRoot 'app'
$expectedVersion = '1.6.1'
$expectedBuild = 15
$releaseTag = 'phone-v1.6.1'
$packageName = 'com.yuanfang.aitext.personal_ai_inbox'
$expectedCertificate = '51b5e2f3f44ce9374cb680a0173c6498a4e13c718c602a355a8b6a50523f4816'
$checks = [System.Collections.Generic.List[object]]::new()
$state = @{
    Serial = $null
    ProcessId = $null
    ArtifactSha256 = $null
}

function Add-ValidationCheck {
    param(
        [string]$Id,
        [ValidateSet('passed', 'failed', 'skipped')]
        [string]$Status,
        [string]$Detail
    )
    $checks.Add([pscustomobject]@{
        id = $Id
        status = $Status
        detail = $Detail
    })
}

function Write-ValidationResult {
    param([string]$Status)
    if (-not (Test-Path -LiteralPath $OutputDir -PathType Container)) {
        return
    }
    $fileName = if ($Stage -eq 'Candidate') {
        'candidate-result.json'
    } else {
        'published-result.json'
    }
    $path = Join-Path $OutputDir $fileName
    $temporary = "$path.tmp"
    $result = [pscustomobject]@{
        stage = $Stage
        status = $Status
        version = $expectedVersion
        buildNumber = $expectedBuild
        avdName = $AvdName
        deviceSerial = $state.Serial
        artifactSha256 = $state.ArtifactSha256
        checks = @($checks)
    }
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporary -Encoding UTF8
    Move-Item -LiteralPath $temporary -Destination $path -Force
}

function Assert-AbsoluteETarget {
    param([string]$Path, [string]$Label)
    if (-not [IO.Path]::IsPathRooted($Path)) {
        throw "$Label must be an absolute path: $Path"
    }
    $full = [IO.Path]::GetFullPath($Path)
    if ([IO.Path]::GetPathRoot($full) -ne 'E:\') {
        throw "$Label must resolve on drive E: $full"
    }
    $cursor = $full
    while ($cursor) {
        $item = Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "$Label must not use a reparse point or directory junction: $cursor"
        }
        $parent = Split-Path -Parent $cursor
        if (-not $parent -or $parent -eq $cursor) { break }
        $cursor = $parent
    }
    return $full.TrimEnd('\')
}

function Assert-EPathExists {
    param([string]$Path, [string]$Label, [switch]$Directory)
    $full = Assert-AbsoluteETarget -Path $Path -Label $Label
    if (-not (Test-Path -LiteralPath $full)) {
        throw "$Label does not exist: $full"
    }
    if ($Directory -and -not (Test-Path -LiteralPath $full -PathType Container)) {
        throw "$Label is not a directory: $full"
    }
    return $full
}

function Get-LatestBuildTool {
    param([string]$SdkRoot, [string]$Name)
    $tool = Get-ChildItem -LiteralPath (Join-Path $SdkRoot 'build-tools') -Directory |
        Sort-Object { [version]$_.Name } -Descending |
        ForEach-Object { Join-Path $_.FullName $Name } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1
    if (-not $tool) {
        throw "Android build tool was not found: $Name"
    }
    return $tool
}

function Invoke-LoggedCommand {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$WorkingDirectory,
        [string]$LogPath
    )
    Push-Location $WorkingDirectory
    try {
        $output = & $FilePath @Arguments 2>&1
        $exitCode = $LASTEXITCODE
        $output | Set-Content -LiteralPath $LogPath -Encoding UTF8
        if ($exitCode -ne 0) {
            $tail = @($output | Select-Object -Last 30) -join [Environment]::NewLine
            throw "$([IO.Path]::GetFileName($FilePath)) exited $exitCode. See $LogPath`n$tail"
        }
        return $output
    } finally {
        Pop-Location
    }
}

function Get-ConnectedEmulatorSerials {
    param([string]$Adb)
    $lines = & $Adb devices
    if ($LASTEXITCODE -ne 0) {
        throw 'adb devices failed.'
    }
    return @(
        $lines |
            ForEach-Object {
                if ($_ -match '^(emulator-\d+)\s+(device|offline)$') {
                    $Matches[1]
                }
            } |
            Sort-Object -Unique
    )
}

function Get-AvdDataPath {
    param([string]$SdkRoot, [string]$AvdHome, [string]$Name)
    $ini = Join-Path $AvdHome "$Name.ini"
    if (-not (Test-Path -LiteralPath $ini -PathType Leaf)) {
        throw "AVD metadata was not found: $ini"
    }
    $iniText = Get-Content -Raw -LiteralPath $ini
    $pathMatch = [regex]::Match($iniText, '(?m)^path=(.+?)\s*$')
    if (-not $pathMatch.Success) {
        throw "AVD path is missing from $ini"
    }
    $dataPath = Assert-EPathExists -Path $pathMatch.Groups[1].Value.Trim() -Label 'AVD data path' -Directory
    $configPath = Join-Path $dataPath 'config.ini'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        throw "AVD config was not found: $configPath"
    }
    $config = Get-Content -Raw -LiteralPath $configPath
    $imageMatch = [regex]::Match($config, '(?m)^image\.sysdir\.1\s*=\s*(.+?)\s*$')
    if (-not $imageMatch.Success) {
        throw "AVD system image is missing from $configPath"
    }
    $relativeImage = $imageMatch.Groups[1].Value.Trim().Replace('/', '\')
    $systemImage = Assert-EPathExists `
        -Path (Join-Path $SdkRoot $relativeImage) `
        -Label 'AVD system image' `
        -Directory
    [pscustomobject]@{
        DataPath = $dataPath
        SystemImage = $systemImage
    }
}

function Assert-AvdNotOccupied {
    param([string]$Name)
    $pattern = "(?i)(?:^|\s)-avd(?:=|\s+)(?:`"$([regex]::Escape($Name))`"|$([regex]::Escape($Name)))(?:\s|$)"
    $processes = @(
        Get-CimInstance Win32_Process |
            Where-Object {
                $_.Name -in @('emulator.exe', 'qemu-system-x86_64-headless.exe') -and
                $_.CommandLine -match $pattern
            }
    )
    if ($processes.Count -gt 0) {
        $details = $processes | ForEach-Object { "$($_.Name):$($_.ProcessId)" }
        throw "Target AVD $Name is already occupied by: $($details -join ', ')"
    }
}

function Move-StaleAvdLocks {
    param(
        [string]$AvdHome,
        [string]$Name,
        [string]$OutputDir
    )
    $avdDir = Join-Path $AvdHome "$Name.avd"
    $backupDir = Join-Path $OutputDir ('runtime\stale-avd-locks-' + (Get-Date -Format 'yyyyMMddHHmmss'))
    $lockNames = @(
        'hardware-qemu.ini.lock',
        'multiinstance.lock',
        'snapshot.lock.lock'
    )
    foreach ($lockName in $lockNames) {
        $source = Join-Path $avdDir $lockName
        if (-not (Test-Path -LiteralPath $source)) { continue }
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        Move-Item -LiteralPath $source -Destination (Join-Path $backupDir $lockName) -Force
    }
}

function Get-FreeEmulatorPort {
    foreach ($port in 5554..5682) {
        if (($port - 5554) % 2 -ne 0) { continue }
        $consoleListener = $null
        $adbListener = $null
        try {
            $consoleListener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $port)
            $adbListener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $port + 1)
            $consoleListener.Start()
            $adbListener.Start()
            return $port
        } catch {
        } finally {
            if ($consoleListener) { $consoleListener.Stop() }
            if ($adbListener) { $adbListener.Stop() }
        }
    }
    throw 'No free Android emulator console/ADB port pair was found.'
}

function Start-ValidationAvd {
    param(
        [string]$SdkRoot,
        [string]$AvdHome,
        [string]$AvdName,
        [string]$OutputDir,
        [int]$BootTimeoutSeconds
    )
    $adb = Join-Path $SdkRoot 'platform-tools\adb.exe'
    $emulator = Join-Path $SdkRoot 'emulator\emulator.exe'
    if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) {
        throw "adb was not found: $adb"
    }
    if (-not (Test-Path -LiteralPath $emulator -PathType Leaf)) {
        throw "emulator was not found: $emulator"
    }
    Assert-AvdNotOccupied $AvdName
    Move-StaleAvdLocks -AvdHome $AvdHome -Name $AvdName -OutputDir $OutputDir
    $avd = Get-AvdDataPath -SdkRoot $SdkRoot -AvdHome $AvdHome -Name $AvdName
    $before = @(Get-ConnectedEmulatorSerials -Adb $adb)
    $emulatorPort = Get-FreeEmulatorPort

    $runtimeRoot = Join-Path $OutputDir 'runtime'
    $tempRoot = Join-Path $runtimeRoot 'temp'
    $userHome = Join-Path $runtimeRoot 'android-user'
    $emulatorHome = Join-Path $runtimeRoot 'emulator-home'
    New-Item -ItemType Directory -Path $tempRoot, $userHome, $emulatorHome -Force | Out-Null
    $stdout = Join-Path $runtimeRoot 'emulator.stdout.log'
    $stderr = Join-Path $runtimeRoot 'emulator.stderr.log'
    $environmentNames = @(
        'TEMP',
        'TMP',
        'ANDROID_USER_HOME',
        'ANDROID_AVD_HOME',
        'ANDROID_EMULATOR_HOME',
        'ANDROID_PREFS_ROOT',
        'ANDROID_SDK_HOME'
    )
    $previousEnvironment = @{}
    foreach ($name in $environmentNames) {
        $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    }
    try {
        [Environment]::SetEnvironmentVariable('TEMP', $tempRoot, 'Process')
        [Environment]::SetEnvironmentVariable('TMP', $tempRoot, 'Process')
        [Environment]::SetEnvironmentVariable('ANDROID_USER_HOME', $userHome, 'Process')
        [Environment]::SetEnvironmentVariable('ANDROID_AVD_HOME', $AvdHome, 'Process')
        [Environment]::SetEnvironmentVariable('ANDROID_EMULATOR_HOME', $emulatorHome, 'Process')
        [Environment]::SetEnvironmentVariable('ANDROID_PREFS_ROOT', $userHome, 'Process')
        [Environment]::SetEnvironmentVariable('ANDROID_SDK_HOME', $userHome, 'Process')
        $process = Start-Process `
            -FilePath $emulator `
            -ArgumentList @(
                '-avd', $AvdName,
                '-port', $emulatorPort,
                '-no-snapshot-save',
                '-no-boot-anim',
                '-no-window',
                '-no-metrics',
                '-gpu', 'swiftshader_indirect'
            ) `
            -PassThru `
            -WindowStyle Hidden `
            -RedirectStandardOutput $stdout `
            -RedirectStandardError $stderr
    } finally {
        foreach ($name in $environmentNames) {
            if ($null -eq $previousEnvironment[$name]) {
                Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
            } else {
                [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], 'Process')
            }
        }
    }

    $deadline = [DateTime]::UtcNow.AddSeconds($BootTimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $process.Refresh()
        if ($process.HasExited) {
            throw "Emulator exited before boot with code $($process.ExitCode). See $stderr"
        }
        $newSerials = @(
            Get-ConnectedEmulatorSerials -Adb $adb |
                Where-Object { $before -notcontains $_ }
        )
        if ($newSerials.Count -eq 1) {
            $serial = $newSerials[0]
            $avdNameOutput = & $adb -s $serial emu avd name 2>&1
            if ($LASTEXITCODE -eq 0 -and ($avdNameOutput -join "`n") -match "(?m)^$([regex]::Escape($AvdName))\s*$") {
                $boot = (& $adb -s $serial shell getprop sys.boot_completed 2>$null | Out-String).Trim()
                if ($boot -eq '1') {
                    return [pscustomobject]@{
                        Serial = $serial
                        ProcessId = [int]$process.Id
                        DataPath = $avd.DataPath
                    }
                }
            }
        }
        if ($newSerials.Count -gt 1) {
            throw "More than one new emulator serial appeared: $($newSerials -join ', ')"
        }
        Start-Sleep -Milliseconds 500
    }
    throw "Emulator did not finish booting within $BootTimeoutSeconds seconds. See $stderr"
}

function Stop-ValidationAvd {
    param(
        [string]$SdkRoot,
        [string]$Serial,
        [int]$ProcessId
    )
    if (-not $Serial) { return }
    $adb = Join-Path $SdkRoot 'platform-tools\adb.exe'
    & $adb -s $Serial emu kill 2>$null | Out-Null
    for ($index = 0; $index -lt 40; $index++) {
        $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        if (-not $process) { break }
        Start-Sleep -Milliseconds 250
    }
    $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($process) {
        Stop-Process -Id $ProcessId -Force
    }
}

function Get-ApkFacts {
    param([string]$ApkPath, [string]$SdkRoot)
    $aapt = Get-LatestBuildTool -SdkRoot $SdkRoot -Name 'aapt2.exe'
    $badging = (& $aapt dump badging $ApkPath 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) {
        throw "aapt2 could not inspect $ApkPath"
    }
    $versionName = [regex]::Match($badging, "versionName='([^']+)'")
    $versionCode = [regex]::Match($badging, "versionCode='(\d+)'")
    $minSdk = [regex]::Match($badging, "minSdkVersion:'(\d+)'")
    $targetSdk = [regex]::Match($badging, "targetSdkVersion:'(\d+)'")
    if (-not $versionName.Success -or -not $versionCode.Success -or -not $minSdk.Success -or -not $targetSdk.Success) {
        throw 'Unable to read APK version or SDK metadata.'
    }
    $manifestTree = (& $aapt dump xmltree $ApkPath --file AndroidManifest.xml 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) {
        throw 'aapt2 could not inspect the Android manifest.'
    }
    [pscustomobject]@{
        VersionName = $versionName.Groups[1].Value
        VersionCode = [int]$versionCode.Groups[1].Value
        MinSdk = [int]$minSdk.Groups[1].Value
        TargetSdk = [int]$targetSdk.Groups[1].Value
        Debuggable = $manifestTree -match 'android:debuggable\([^)]*\)=\(type 0x12\)0x1'
    }
}

function Test-PublishedApk {
    param(
        [string]$ApkPath,
        [string]$ChecksumsPath,
        [string]$SdkRoot,
        [string]$ExpectedVersion,
        [int]$ExpectedBuild,
        [string]$ExpectedCertificateSha256
    )
    if (-not (Test-Path -LiteralPath $ApkPath -PathType Leaf)) {
        throw "APK was not found: $ApkPath"
    }
    if (-not (Test-Path -LiteralPath $ChecksumsPath -PathType Leaf)) {
        throw "Checksum manifest was not found: $ChecksumsPath"
    }
    if ($ExpectedVersion -notmatch '^\d+\.\d+\.\d+$' -or $ExpectedBuild -le 0) {
        throw 'Expected APK version is invalid.'
    }
    $normalizedExpectedCertificate = $ExpectedCertificateSha256.Replace(':', '').ToLowerInvariant()
    if ($normalizedExpectedCertificate -notmatch '^[0-9a-f]{64}$') {
        throw 'Expected certificate SHA-256 must contain 64 hexadecimal digits.'
    }

    $apkName = Split-Path -Leaf $ApkPath
    $checksumMatches = @()
    foreach ($line in Get-Content -LiteralPath $ChecksumsPath) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $match = [regex]::Match($line.Trim(), '^([0-9a-fA-F]{64})\s+\*?(.+)$')
        if ($match.Success -and $match.Groups[2].Value -eq $apkName) {
            $checksumMatches += $match
        }
    }
    if ($checksumMatches.Count -ne 1) {
        throw "Expected exactly one checksum entry for $apkName; found $($checksumMatches.Count)."
    }
    $sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $ApkPath).Hash.ToLowerInvariant()
    if ($sha256 -ne $checksumMatches[0].Groups[1].Value.ToLowerInvariant()) {
        throw "APK SHA-256 does not match SHA256SUMS.txt: $sha256"
    }

    $facts = Get-ApkFacts -ApkPath $ApkPath -SdkRoot $SdkRoot
    if ($facts.VersionName -ne $ExpectedVersion) {
        throw "APK versionName mismatch: $($facts.VersionName)"
    }
    if ($facts.VersionCode -ne $ExpectedBuild) {
        throw "APK versionCode mismatch: $($facts.VersionCode)"
    }
    if ($facts.MinSdk -ne 24 -or $facts.TargetSdk -ne 36) {
        throw "APK SDK mismatch: min=$($facts.MinSdk), target=$($facts.TargetSdk)"
    }
    if ($facts.Debuggable) {
        throw 'Published APK is debuggable.'
    }

    $apksigner = Get-LatestBuildTool -SdkRoot $SdkRoot -Name 'apksigner.bat'
    $signature = (& $apksigner verify --verbose --print-certs $ApkPath 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) {
        throw 'apksigner verification failed.'
    }
    if ($signature -notmatch 'Verified using v2 scheme \(APK Signature Scheme v2\):\s*true') {
        throw 'APK does not have a valid v2 signature.'
    }
    $certificateMatch = [regex]::Match(
        $signature,
        'certificate SHA-256 digest:\s*([0-9a-fA-F:]+)'
    )
    if (-not $certificateMatch.Success) {
        throw 'Unable to read the APK signing certificate.'
    }
    $certificate = $certificateMatch.Groups[1].Value.Replace(':', '').ToLowerInvariant()
    if ($certificate -ne $normalizedExpectedCertificate) {
        throw "APK signing certificate mismatch: $certificate"
    }
    [pscustomobject]@{
        Sha256 = $sha256
        CertificateSha256 = $certificate
        VersionName = $facts.VersionName
        VersionCode = $facts.VersionCode
        MinSdk = $facts.MinSdk
        TargetSdk = $facts.TargetSdk
    }
}

function Invoke-SqliteSeed {
    param(
        [string]$SdkRoot,
        [string]$DatabasePath,
        [string]$Sql
    )
    $sqliteDll = @(
        (Join-Path $appRoot 'build\native_assets\windows\sqlite3.dll'),
        (Get-ChildItem `
            -Path (Join-Path $appRoot '.dart_tool\hooks_runner\shared\sqlite3\build') `
            -Filter sqlite3.dll `
            -Recurse `
            -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName)
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
    if (-not $sqliteDll) {
        throw "Windows sqlite3.dll was not found: $sqliteDll"
    }
    if (-not ([System.Management.Automation.PSTypeName]'AitextSqliteSeed').Type) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class AitextSqliteSeed {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr LoadLibraryW(string path);

    [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int sqlite3_open_v2(string filename, out IntPtr database, int flags, IntPtr vfs);

    [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int sqlite3_exec(IntPtr database, string sql, IntPtr callback, IntPtr argument, out IntPtr errorMessage);

    [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr sqlite3_errmsg(IntPtr database);

    [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr sqlite3_column_text(IntPtr statement, int column);

    [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern void sqlite3_free(IntPtr value);

    [DllImport("sqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int sqlite3_close_v2(IntPtr database);

    public static void Execute(string libraryPath, string databasePath, string sql) {
        if (LoadLibraryW(libraryPath) == IntPtr.Zero) {
            throw new InvalidOperationException("Unable to load sqlite3.dll.");
        }
        IntPtr database;
        int openResult = sqlite3_open_v2(databasePath, out database, 6, IntPtr.Zero);
        if (openResult != 0) {
            string openError = database == IntPtr.Zero
                ? "Unable to open SQLite database."
                : Marshal.PtrToStringUTF8(sqlite3_errmsg(database)) ?? "Unable to open SQLite database.";
            if (database != IntPtr.Zero) sqlite3_close_v2(database);
            throw new InvalidOperationException(openError);
        }
        IntPtr errorMessage;
        int result = sqlite3_exec(database, sql, IntPtr.Zero, IntPtr.Zero, out errorMessage);
        string error = result == 0
            ? null
            : Marshal.PtrToStringUTF8(errorMessage) ?? "SQLite execution failed.";
        if (errorMessage != IntPtr.Zero) sqlite3_free(errorMessage);
        sqlite3_close_v2(database);
        if (result != 0) throw new InvalidOperationException(error);
    }
}
'@
    }
    [AitextSqliteSeed]::Execute($sqliteDll, $DatabasePath, $Sql)
}

function Remove-ScopedValidationDirectory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $full = Assert-AbsoluteETarget -Path $Path -Label 'validation subdirectory'
    $outputPrefix = (Assert-AbsoluteETarget -Path $OutputDir -Label 'output directory').TrimEnd('\') + '\'
    if (-not $full.StartsWith($outputPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove a directory outside OutputDir: $full"
    }
    Remove-Item -LiteralPath $full -Recurse -Force
}

function Invoke-CandidateStage {
    param($Context)
    $flutter = 'E:\DevTools\Flutter\bin\flutter.bat'
    if (-not (Test-Path -LiteralPath $flutter -PathType Leaf)) {
        throw "Flutter was not found: $flutter"
    }
    $logs = Join-Path $OutputDir 'candidate'
    New-Item -ItemType Directory -Path $logs -Force | Out-Null

    Invoke-LoggedCommand `
        -FilePath $flutter `
        -Arguments @('config', '--android-sdk', $SdkRoot) `
        -WorkingDirectory $appRoot `
        -LogPath (Join-Path $logs 'flutter-config.log') | Out-Null
    Invoke-LoggedCommand `
        -FilePath $flutter `
        -Arguments @('pub', 'get') `
        -WorkingDirectory $appRoot `
        -LogPath (Join-Path $logs 'pub-get.log') | Out-Null
    Add-ValidationCheck 'environment.avd-e-drive' 'passed' "SDK=$SdkRoot; AVD=$($Context.DataPath); serial=$($Context.Serial)"

    Invoke-LoggedCommand `
        -FilePath $flutter `
        -Arguments @(
            'test', '--no-pub', '--reporter', 'expanded',
            'test/chat_activity_test.dart',
            'test/chat_service_agent_test.dart',
            'test/secretary_conversation_ui_test.dart',
            'test/conversation_large_history_ui_test.dart'
        ) `
        -WorkingDirectory $appRoot `
        -LogPath (Join-Path $logs 'host-tests.log') | Out-Null
    Add-ValidationCheck 'host.activity-projection' 'passed' '活动投影、服务时序、秘书 UI 与大历史定向测试通过。'
    Add-ValidationCheck 'host.chat-service' 'passed' 'chat_service_agent_test.dart 通过。'
    Add-ValidationCheck 'host.secretary-ui' 'passed' 'secretary_conversation_ui_test.dart 通过。'
    Add-ValidationCheck 'host.large-history' 'passed' 'conversation_large_history_ui_test.dart 通过。'

    $gradlew = Join-Path $appRoot 'android\gradlew.bat'
    if (Test-Path -LiteralPath $gradlew -PathType Leaf) {
        Invoke-LoggedCommand `
            -FilePath $gradlew `
            -Arguments @('--stop') `
            -WorkingDirectory (Join-Path $appRoot 'android') `
            -LogPath (Join-Path $logs 'gradle-stop.log') | Out-Null
    }
    Invoke-LoggedCommand `
        -FilePath $flutter `
        -Arguments @('build', 'apk', '--debug', '--no-pub', '-v') `
        -WorkingDirectory $appRoot `
        -LogPath (Join-Path $logs 'build-debug.log') | Out-Null
    $builtApk = Join-Path $appRoot 'build\app\outputs\flutter-apk\app-debug.apk'
    if (-not (Test-Path -LiteralPath $builtApk -PathType Leaf)) {
        throw "Debug APK was not produced: $builtApk"
    }
    $candidateApk = Join-Path $OutputDir 'candidate-app-debug.apk'
    Copy-Item -LiteralPath $builtApk -Destination $candidateApk -Force
    $state.ArtifactSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $candidateApk).Hash.ToLowerInvariant()
    $facts = Get-ApkFacts -ApkPath $candidateApk -SdkRoot $SdkRoot
    if ($facts.VersionName -ne $expectedVersion -or $facts.VersionCode -ne $expectedBuild -or $facts.MinSdk -ne 24 -or $facts.TargetSdk -ne 36) {
        throw "Candidate APK metadata mismatch: $($facts | ConvertTo-Json -Compress)"
    }
    Add-ValidationCheck 'build.candidate-apk' 'passed' "sha256=$($state.ArtifactSha256); version=$($facts.VersionName)+$($facts.VersionCode); sdk=$($facts.MinSdk)/$($facts.TargetSdk)"

    Invoke-LoggedCommand `
        -FilePath $flutter `
        -Arguments @(
            'test', '--no-pub',
            'integration_test/secretary_activity_phone_test.dart',
            '-d', $Context.Serial,
            '--reporter', 'expanded',
            '-v'
        ) `
        -WorkingDirectory $appRoot `
        -LogPath (Join-Path $logs 'device-test.log') | Out-Null
    Add-ValidationCheck 'environment.avd-boot' 'passed' "AVD $AvdName 已启动并完成 boot，serial=$($Context.Serial)。"
    foreach ($id in @(
        'device.activity-before-first-token',
        'device.activity-tool-running',
        'device.activity-tool-returned',
        'device.activity-completed-fold',
        'device.activity-stopped-fold',
        'device.activity-failed-fold',
        'device.activity-history-reopen',
        'device.activity-privacy',
        'device.theme-light',
        'device.theme-dark',
        'device.layout-narrow',
        'device.layout-wide',
        'device.scroll-follow',
        'device.reopen-persistence'
    )) {
        Add-ValidationCheck $id 'passed' 'Android 集成测试场景通过。'
    }
    $screenshotRemote = '/sdcard/secretary-activity-candidate.png'
    & (Join-Path $SdkRoot 'platform-tools\adb.exe') -s $Context.Serial shell screencap -p $screenshotRemote | Out-Null
    & (Join-Path $SdkRoot 'platform-tools\adb.exe') -s $Context.Serial pull $screenshotRemote (Join-Path $logs 'candidate.png') | Out-Null
}

function Invoke-PublishedStage {
    param($Context)
    $releaseDir = Join-Path $OutputDir 'published'
    Remove-ScopedValidationDirectory $releaseDir
    New-Item -ItemType Directory -Path $releaseDir -Force | Out-Null
    $gh = (Get-Command gh -ErrorAction Stop).Source
    $releaseJson = & $gh release view $releaseTag --json tagName,isPrerelease,isDraft,assets
    if ($LASTEXITCODE -ne 0) {
        throw "GitHub release was not found: $releaseTag"
    }
    $release = $releaseJson | ConvertFrom-Json
    $assetNames = @($release.assets | ForEach-Object name)
    $apkName = "personal-ai-inbox-v$expectedVersion-android.apk"
    if ($release.tagName -ne $releaseTag -or -not $release.isPrerelease -or $release.isDraft) {
        throw 'Release tag or pre-release metadata is invalid.'
    }
    foreach ($required in @($apkName, 'SHA256SUMS.txt')) {
        if ($assetNames -notcontains $required) {
            throw "Release asset is missing: $required"
        }
    }
    Add-ValidationCheck 'release.metadata' 'passed' "tag=$releaseTag; prerelease=true; draft=false"
    Add-ValidationCheck 'release.assets' 'passed' ($assetNames -join ', ')

    foreach ($pattern in @($apkName, 'SHA256SUMS.txt')) {
        & $gh release download $releaseTag --pattern $pattern --dir $releaseDir --clobber
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to download release asset: $pattern"
        }
    }
    $apk = Join-Path $releaseDir $apkName
    $checksums = Join-Path $releaseDir 'SHA256SUMS.txt'
    $published = Test-PublishedApk `
        -ApkPath $apk `
        -ChecksumsPath $checksums `
        -SdkRoot $SdkRoot `
        -ExpectedVersion $expectedVersion `
        -ExpectedBuild $expectedBuild `
        -ExpectedCertificateSha256 $expectedCertificate
    $state.ArtifactSha256 = $published.Sha256
    Add-ValidationCheck 'apk.checksum' 'passed' "sha256=$($published.Sha256)"
    Add-ValidationCheck 'apk.version' 'passed' "versionName=$($published.VersionName); versionCode=$($published.VersionCode)"
    Add-ValidationCheck 'apk.sdk' 'passed' "minSdk=$($published.MinSdk); targetSdk=$($published.TargetSdk)"
    Add-ValidationCheck 'apk.debuggable' 'passed' 'application debug=false'
    Add-ValidationCheck 'apk.signature' 'passed' "v2=true; certificate=$($published.CertificateSha256)"

    $previousDir = Join-Path $OutputDir 'previous-v1.6.0'
    Remove-ScopedValidationDirectory $previousDir
    New-Item -ItemType Directory -Path $previousDir -Force | Out-Null
    $previousApkName = 'personal-ai-inbox-v1.6.0-android.apk'
    foreach ($pattern in @($previousApkName, 'SHA256SUMS.txt')) {
        & $gh release download 'phone-v1.6.0' --pattern $pattern --dir $previousDir --clobber
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to download previous release asset: $pattern"
        }
    }
    $previousApk = Join-Path $previousDir $previousApkName
    $previousPublished = Test-PublishedApk `
        -ApkPath $previousApk `
        -ChecksumsPath (Join-Path $previousDir 'SHA256SUMS.txt') `
        -SdkRoot $SdkRoot `
        -ExpectedVersion '1.6.0' `
        -ExpectedBuild 14 `
        -ExpectedCertificateSha256 $expectedCertificate

    $adb = Join-Path $SdkRoot 'platform-tools\adb.exe'
    & $adb -s $Context.Serial uninstall $packageName 2>$null | Out-Null
    & $adb -s $Context.Serial install $previousApk
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to install the previous public APK.'
    }
    Add-ValidationCheck 'upgrade.previous-install' 'passed' "v1.6.0+14 已安装；sha256=$($previousPublished.Sha256)。"

    & $adb -s $Context.Serial root 2>&1 | Out-Null
    $rootReady = $false
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        $devices = & $adb devices
        if ($devices -match "(?m)^$([regex]::Escape($Context.Serial))\s+device$") {
            $identity = (& $adb -s $Context.Serial shell id 2>$null | Out-String).Trim()
            if ($identity -match '\buid=0\b') {
                $rootReady = $true
                break
            }
        }
        Start-Sleep -Seconds 1
    }
    if (-not $rootReady) {
        throw "adb root did not become ready for $($Context.Serial)."
    }

    $fixture = Join-Path $OutputDir 'retention-fixture'
    Remove-ScopedValidationDirectory $fixture
    New-Item -ItemType Directory -Path $fixture -Force | Out-Null
    $dataDir = "/data/user/0/$packageName/files"
    & $adb -s $Context.Serial shell mkdir -p $dataDir | Out-Null
    $owner = (& $adb -s $Context.Serial shell stat -c '%u:%g' "/data/user/0/$packageName" | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $owner -notmatch '^\d+:\d+$') {
        throw "Unable to determine app data ownership: $owner"
    }

    $conversationDb = Join-Path $fixture 'conversations.sqlite3'
    $timestamp = '2026-11-12T12:00:00+08:00'
    $sql = @"
PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;
CREATE TABLE IF NOT EXISTS conversations (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  auto_title INTEGER NOT NULL,
  preview TEXT NOT NULL,
  ai_permissions_json TEXT NOT NULL,
  ai_policy_json TEXT
);
CREATE TABLE IF NOT EXISTS chat_messages (
  id TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL,
  role TEXT NOT NULL,
  content TEXT NOT NULL,
  status TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  attachments_json TEXT NOT NULL,
  actions_json TEXT NOT NULL,
  error TEXT,
  reasoning_content TEXT NOT NULL,
  tool_transcript_json TEXT NOT NULL,
  FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_chat_messages_conversation
  ON chat_messages(conversation_id, created_at);
CREATE TABLE IF NOT EXISTS generation_runs (
  assistant_message_id TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL,
  user_message_id TEXT NOT NULL,
  status TEXT NOT NULL,
  response_text TEXT NOT NULL,
  tool_calls_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  error TEXT
);
CREATE TABLE IF NOT EXISTS agent_trash_entries (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  payload_json TEXT NOT NULL
);
INSERT OR REPLACE INTO conversations
  (id, title, created_at, updated_at, auto_title, preview, ai_permissions_json, ai_policy_json)
VALUES
  ('conv_phone_retention_v161', 'PHONE_RETENTION_V161 conversation', '$timestamp', '$timestamp', 0, 'PHONE_RETENTION_V161', '{"read":true,"create":true,"modify_delete":true}', NULL);
INSERT OR REPLACE INTO chat_messages
  (id, conversation_id, role, content, status, created_at, updated_at, attachments_json, actions_json, error, reasoning_content, tool_transcript_json)
VALUES
  ('msg_phone_retention_v161', 'conv_phone_retention_v161', 'user', 'PHONE_RETENTION_V161 message', 'complete', '$timestamp', '$timestamp', '[]', '[]', NULL, '', '[]');
PRAGMA user_version=7;
PRAGMA wal_checkpoint(TRUNCATE);
"@
    Invoke-SqliteSeed -SdkRoot $SdkRoot -DatabasePath $conversationDb -Sql $sql
    $tableDir = Join-Path $fixture 'vault\tables'
    $itemDir = Join-Path $fixture 'vault\items'
    New-Item -ItemType Directory -Path $tableDir, $itemDir -Force | Out-Null
    $table = @'
---
schema_version: 1
id: 'tb_phone_retention_v161'
type: 'table'
role: 'custom'
title: 'PHONE_RETENTION_V161 table'
revision: 1
created_at: '2026-11-12T12:00:00.000+08:00'
updated_at: '2026-11-12T12:00:00.000+08:00'
deleted: false
field_definitions: []
---

PHONE_RETENTION_V161 table body
'@
    $item = @'
---
schema_version: 1
id: 'it_phone_retention_v161'
type: 'note'
table_id: 'tb_phone_retention_v161'
title: 'PHONE_RETENTION_V161 entry'
revision: 1
created_at: '2026-11-12T12:00:00.000+08:00'
updated_at: '2026-11-12T12:00:00.000+08:00'
deleted: false
---

PHONE_RETENTION_V161 entry body
'@
    Set-Content -LiteralPath (Join-Path $tableDir 'tb_phone_retention_v161.md') -Value $table -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $itemDir 'it_phone_retention_v161.md') -Value $item -Encoding UTF8

    & $adb -s $Context.Serial push $conversationDb "$dataDir/conversations.sqlite3" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to push the retention conversation database.' }
    & $adb -s $Context.Serial shell mkdir -p "$dataDir/vault/tables" "$dataDir/vault/items" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to create the retention vault directories.' }
    & $adb -s $Context.Serial push (Join-Path $tableDir 'tb_phone_retention_v161.md') "$dataDir/vault/tables/tb_phone_retention_v161.md" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to push the retention table fixture.' }
    & $adb -s $Context.Serial push (Join-Path $itemDir 'it_phone_retention_v161.md') "$dataDir/vault/items/it_phone_retention_v161.md" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to push the retention item fixture.' }
    & $adb -s $Context.Serial shell chown -R $owner $dataDir | Out-Null
    & $adb -s $Context.Serial shell chmod -R u+rwX $dataDir | Out-Null
    & $adb -s $Context.Serial shell rm -f `
        "$dataDir/conversations.sqlite3-wal" `
        "$dataDir/conversations.sqlite3-shm" | Out-Null
    Add-ValidationCheck 'upgrade.synthetic-data' 'passed' '已写入可识别的合成会话、表和条目。'

    & $adb -s $Context.Serial shell input keyevent 82 | Out-Null
    & $adb -s $Context.Serial shell wm dismiss-keyguard | Out-Null
    & $adb -s $Context.Serial shell monkey -p $packageName -c android.intent.category.LAUNCHER 1 | Out-Null
    Start-Sleep -Seconds 3
    & $adb -s $Context.Serial shell am force-stop $packageName | Out-Null

    & $adb -s $Context.Serial install -r $apk
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to overwrite-install the published APK.'
    }
    Add-ValidationCheck 'upgrade.overwrite-install' 'passed' 'v1.6.1+15 覆盖安装成功。'
    & $adb -s $Context.Serial shell monkey -p $packageName -c android.intent.category.LAUNCHER 1 | Out-Null
    Start-Sleep -Seconds 4
    $packageDump = (& $adb -s $Context.Serial shell dumpsys package $packageName | Out-String)
    if ($packageDump -notmatch "versionCode=$expectedBuild\b" -or $packageDump -notmatch "versionName=$([regex]::Escape($expectedVersion))\b") {
        throw 'Installed package version did not update to 1.6.1+15.'
    }
    $verificationDir = Join-Path $releaseDir 'upgrade-verify'
    Remove-ScopedValidationDirectory $verificationDir
    New-Item -ItemType Directory -Path $verificationDir -Force | Out-Null
    $conversationBytes = [System.Collections.Generic.List[byte]]::new()
    foreach ($suffix in @('', '-wal')) {
        $remote = "$dataDir/conversations.sqlite3$suffix"
        & $adb -s $Context.Serial shell test -f $remote
        if ($LASTEXITCODE -ne 0) { continue }
        $local = Join-Path $verificationDir "conversations.sqlite3$suffix"
        & $adb -s $Context.Serial pull $remote $local | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Unable to pull upgraded conversation file: $remote" }
        $conversationBytes.AddRange([IO.File]::ReadAllBytes($local))
    }
    $conversationMarker = [Text.Encoding]::UTF8.GetString($conversationBytes.ToArray())
    foreach ($relative in @(
        'vault/tables/tb_phone_retention_v161.md',
        'vault/items/it_phone_retention_v161.md'
    )) {
        $remote = "$dataDir/$relative"
        & $adb -s $Context.Serial shell test -f $remote
        if ($LASTEXITCODE -ne 0) {
            throw "Retention file is missing after upgrade: $relative"
        }
        $local = Join-Path $verificationDir $relative.Replace('/', '\')
        New-Item -ItemType Directory -Path (Split-Path -Parent $local) -Force | Out-Null
        & $adb -s $Context.Serial pull $remote $local | Out-Null
        if ($LASTEXITCODE -ne 0 -or (Get-Content -Raw -LiteralPath $local) -notmatch 'PHONE_RETENTION_V161') {
            throw "Retention marker is missing after upgrade: $relative"
        }
    }
    if ($conversationMarker -notmatch 'PHONE_RETENTION_V161') {
        throw 'Synthetic conversation marker was not retained after upgrade.'
    }
    Add-ValidationCheck 'upgrade.data-retained' 'passed' '覆盖启动后合成会话、表和条目标记均可读回。'
    $screenshotRemote = '/sdcard/secretary-activity-published.png'
    & $adb -s $Context.Serial shell screencap -p $screenshotRemote | Out-Null
    & $adb -s $Context.Serial pull $screenshotRemote (Join-Path $releaseDir 'published.png') | Out-Null
}

$exitCode = 0
try {
    $SdkRoot = Assert-EPathExists -Path $SdkRoot -Label 'SdkRoot' -Directory
    $AvdHome = Assert-EPathExists -Path $AvdHome -Label 'AvdHome' -Directory
    $OutputDir = Assert-AbsoluteETarget -Path $OutputDir -Label 'OutputDir'
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    $env:FLUTTER_ROOT = 'E:\DevTools\Flutter'
    $env:ANDROID_HOME = $SdkRoot
    $env:ANDROID_SDK_ROOT = $SdkRoot
    $javaHome = 'C:\Program Files\Java\jdk-17.0.2'
    if (Test-Path -LiteralPath $javaHome -PathType Container) {
        $env:JAVA_HOME = $javaHome
    }

    $context = Start-ValidationAvd `
        -SdkRoot $SdkRoot `
        -AvdHome $AvdHome `
        -AvdName $AvdName `
        -OutputDir $OutputDir `
        -BootTimeoutSeconds $BootTimeoutSeconds
    $state.Serial = $context.Serial
    $state.ProcessId = $context.ProcessId
    if ($Stage -eq 'Candidate') {
        Invoke-CandidateStage $context
    } else {
        Invoke-PublishedStage $context
    }
    Write-ValidationResult 'passed'
} catch {
    $exitCode = 1
    Add-ValidationCheck 'execution' 'failed' $_.Exception.Message
    try {
        Write-ValidationResult 'failed'
    } catch {
        Write-Error "Failed to write validation result: $($_.Exception.Message)"
    }
    Write-Error $_
} finally {
    if ($state.Serial -and $state.ProcessId) {
        try {
            Stop-ValidationAvd `
                -SdkRoot $SdkRoot `
                -Serial $state.Serial `
                -ProcessId $state.ProcessId
        } catch {
            Write-Warning "AVD cleanup failed: $($_.Exception.Message)"
        }
    }
}

exit $exitCode
