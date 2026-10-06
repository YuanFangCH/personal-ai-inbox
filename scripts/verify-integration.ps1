param(
    [string]$AndroidDevice = 'emulator-5554',
    [switch]$SkipWindows,
    [switch]$SkipAndroid
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$appRoot = Join-Path $repoRoot 'app'
$flutter = (Get-Command flutter -ErrorAction Stop).Source

Push-Location $appRoot
try {
    if (-not $SkipWindows) {
        & $flutter test integration_test/windows_smoke_test.dart -d windows --reporter expanded
        if ($LASTEXITCODE -ne 0) { throw 'Windows integration test failed' }
    }

    if (-not $SkipAndroid) {
        if (-not $env:ANDROID_HOME) {
            throw 'ANDROID_HOME is required for Android integration verification'
        }
        if (-not $env:JAVA_HOME) {
            throw 'JAVA_HOME is required for Android integration verification'
        }
        $env:GRADLE_OPTS = '-Djavax.net.ssl.trustStoreType=WINDOWS-ROOT'
        & $flutter test integration_test/android_smoke_test.dart -d $AndroidDevice --reporter expanded
        if ($LASTEXITCODE -ne 0) { throw 'Android integration test failed' }
    }
}
finally {
    Pop-Location
}

Write-Output 'Integration verification passed.'
