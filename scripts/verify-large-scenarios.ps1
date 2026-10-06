param(
    [string]$AndroidDevice,
    [switch]$SkipHost,
    [switch]$SkipAndroid
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$appRoot = Join-Path $repoRoot 'app'
$flutter = (Get-Command flutter -ErrorAction Stop).Source

Push-Location $appRoot
try {
    if (-not $SkipHost) {
        & $flutter test test/large_scenario_20_cases_test.dart --reporter expanded
        if ($LASTEXITCODE -ne 0) {
            throw 'Large scenario host matrix failed'
        }
    }

    if (-not $SkipAndroid) {
        if (-not $AndroidDevice) {
            throw 'AndroidDevice is required unless -SkipAndroid is used.'
        }
        if (-not $env:ANDROID_HOME) {
            throw 'ANDROID_HOME is required for Android large scenario verification'
        }
        if (-not $env:JAVA_HOME) {
            throw 'JAVA_HOME is required for Android large scenario verification'
        }
        $env:GRADLE_OPTS = '-Djavax.net.ssl.trustStoreType=WINDOWS-ROOT'
        & $flutter test integration_test/large_scenario_20_test.dart `
            -d $AndroidDevice `
            --reporter expanded
        if ($LASTEXITCODE -ne 0) {
            throw 'Large scenario Android matrix failed'
        }
    }
}
finally {
    Pop-Location
}

Write-Output 'Large scenario verification passed.'
