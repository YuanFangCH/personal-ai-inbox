param(
    [string]$AndroidDevice = 'emulator-5554',
    [switch]$SkipDevice
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$appRoot = Join-Path $repoRoot 'app'
$flutter = (Get-Command flutter -ErrorAction Stop).Source

Push-Location $appRoot
try {
    & $flutter test test/android_ui_100_cases_test.dart --reporter expanded
    if ($LASTEXITCODE -ne 0) { throw 'Android UI host matrix failed' }

    if (-not $SkipDevice) {
        if (-not $env:ANDROID_HOME) {
            throw 'ANDROID_HOME is required for Android UI device verification'
        }
        if (-not $env:JAVA_HOME) {
            throw 'JAVA_HOME is required for Android UI device verification'
        }
        $env:GRADLE_OPTS = '-Djavax.net.ssl.trustStoreType=WINDOWS-ROOT'
        & $flutter test integration_test/android_ui_100_test.dart `
            -d $AndroidDevice --reporter expanded
        if ($LASTEXITCODE -ne 0) { throw 'Android UI device matrix failed' }
    }
}
finally {
    Pop-Location
}

Write-Output 'Android UI verification passed.'
