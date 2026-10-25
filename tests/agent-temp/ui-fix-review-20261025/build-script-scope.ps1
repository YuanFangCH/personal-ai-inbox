$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$names = @('GRADLE_USER_HOME', 'JAVA_TOOL_OPTIONS', 'ANDROID_USER_HOME')
$prior = @{}
foreach ($name in $names) {
    $prior[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
$locationBefore = (Get-Location).Path
try {
    $env:GRADLE_USER_HOME = 'original-gradle-cache'
    $env:JAVA_TOOL_OPTIONS = '-Daitext.original=true'
    Remove-Item -LiteralPath 'Env:ANDROID_USER_HOME' -ErrorAction SilentlyContinue
    $failedAsExpected = $false
    try {
        & (Join-Path $repoRoot 'scripts/build-android-isolated.ps1') `
            -FlutterBin (Join-Path $PSScriptRoot 'failing-flutter.cmd') `
            -GradleUserHome (Join-Path $PSScriptRoot 'gradle-home') `
            -NativeBuildCacheDirectory (Join-Path $PSScriptRoot 'native-cache')
    }
    catch {
        if ($_.Exception.Message -ne 'Android Debug build failed with exit code 23.') { throw }
        $failedAsExpected = $true
    }
    if (-not $failedAsExpected) { throw 'The stub did not fail the build.' }
    if ($env:GRADLE_USER_HOME -ne 'original-gradle-cache') { throw 'Gradle environment not restored.' }
    if ($env:JAVA_TOOL_OPTIONS -ne '-Daitext.original=true') { throw 'Java environment not restored.' }
    if ($null -ne [Environment]::GetEnvironmentVariable('ANDROID_USER_HOME', 'Process')) {
        throw 'An absent Android environment variable was not removed.'
    }
    if ((Get-Location).Path -ne $locationBefore) { throw 'Working directory not restored.' }
    $temporaryInit = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'gradle-home/init.d') -Filter 'aitext-native-*.gradle')
    if ($temporaryInit.Count) { throw 'Temporary native-cache init script was not removed.' }
    Write-Output 'Build helper failure cleanup passed.'
}
finally {
    foreach ($name in $names) {
        if ($null -eq $prior[$name]) {
            Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
        }
        else {
            [Environment]::SetEnvironmentVariable($name, $prior[$name], 'Process')
        }
    }
}
