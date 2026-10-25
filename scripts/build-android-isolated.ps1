param(
    [string]$FlutterBin = 'flutter',
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$GradleUserHome,
    [string]$ProjectCacheDirectory,
    [string]$AndroidUserHome,
    [string]$NativeBuildCacheDirectory,
    [switch]$UseWindowsRootCertificates
)

$ErrorActionPreference = 'Stop'
$flutter = (Get-Command $FlutterBin -ErrorAction Stop).Source
. (Join-Path $PSScriptRoot 'assert-flutter-version.ps1') -FlutterExecutable $flutter

if ($UseWindowsRootCertificates -and $env:OS -ne 'Windows_NT') {
    throw 'Windows root certificates are only available on Windows.'
}

$gradleCache = [IO.Path]::GetFullPath($GradleUserHome)
if (-not $ProjectCacheDirectory) {
    $ProjectCacheDirectory = Join-Path $gradleCache 'project-cache'
}
if (-not $AndroidUserHome) {
    $AndroidUserHome = Join-Path $gradleCache 'android-user'
}
$projectCache = [IO.Path]::GetFullPath($ProjectCacheDirectory)
$androidCache = [IO.Path]::GetFullPath($AndroidUserHome)
New-Item -ItemType Directory -Force -Path $gradleCache, $projectCache, $androidCache | Out-Null

$environmentNames = @('GRADLE_USER_HOME', 'JAVA_TOOL_OPTIONS', 'ANDROID_USER_HOME')
$priorEnvironment = @{}
foreach ($name in $environmentNames) {
    $priorEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

$appRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'app'
$nativeInit = $null
Push-Location $appRoot
try {
    $env:GRADLE_USER_HOME = $gradleCache
    $env:ANDROID_USER_HOME = $androidCache
    $javaOptions = '-Dorg.gradle.projectcachedir="' + $projectCache.Replace('\', '/') + '"'
    if ($UseWindowsRootCertificates) {
        $javaOptions += ' -Djavax.net.ssl.trustStore=NONE -Djavax.net.ssl.trustStoreType=Windows-ROOT'
    }
    if ($NativeBuildCacheDirectory) {
        $nativeCache = [IO.Path]::GetFullPath($NativeBuildCacheDirectory)
        $initDirectory = Join-Path $gradleCache 'init.d'
        New-Item -ItemType Directory -Force -Path $nativeCache, $initDirectory | Out-Null
        $nativeInit = Join-Path $initDirectory ('aitext-native-' + [guid]::NewGuid().ToString('N') + '.gradle')
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'android-isolated-native.gradle') -Destination $nativeInit
        $javaOptions += ' -Daitext.androidProjectRoot="' + (Join-Path $appRoot 'android').Replace('\', '/') + '"'
        $javaOptions += ' -Daitext.nativeBuildCache="' + $nativeCache.Replace('\', '/') + '"'
    }
    # Isolate build options without exposing or persisting the caller's options.
    $env:JAVA_TOOL_OPTIONS = $javaOptions
    & $flutter build apk --debug --no-pub
    if ($LASTEXITCODE -ne 0) {
        throw "Android Debug build failed with exit code $LASTEXITCODE."
    }
}
finally {
    if ($nativeInit -and (Test-Path -LiteralPath $nativeInit)) {
        Remove-Item -LiteralPath $nativeInit
    }
    foreach ($name in $environmentNames) {
        if ($null -eq $priorEnvironment[$name]) {
            Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
        }
        else {
            [Environment]::SetEnvironmentVariable($name, $priorEnvironment[$name], 'Process')
        }
    }
    Pop-Location
}

Write-Output 'Android Debug build passed; process environment restored.'
