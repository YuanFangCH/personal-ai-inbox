param(
    [switch]$SkipAndroid,
    [switch]$SkipWindows
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$appRoot = Join-Path $repoRoot 'app'
$flutter = (Get-Command flutter -ErrorAction Stop).Source

Push-Location $appRoot
try {
    & $flutter analyze
    if ($LASTEXITCODE -ne 0) { throw 'flutter analyze failed' }

    & $flutter test --reporter expanded
    if ($LASTEXITCODE -ne 0) { throw 'flutter test failed' }

    & $flutter build web --release
    if ($LASTEXITCODE -ne 0) { throw 'flutter build web failed' }

    if (-not $SkipWindows) {
        & $flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw 'flutter build windows failed' }
    }

    if (-not $SkipAndroid) {
        if (-not $env:ANDROID_HOME) {
            throw 'ANDROID_HOME is required for Android verification'
        }
        if (-not $env:JAVA_HOME) {
            throw 'JAVA_HOME is required for Android verification'
        }
        $env:GRADLE_OPTS = '-Djavax.net.ssl.trustStoreType=WINDOWS-ROOT'
        & $flutter build apk --release
        if ($LASTEXITCODE -ne 0) { throw 'flutter build apk failed' }
    }
}
finally {
    Pop-Location
}

Write-Output 'App verification passed.'
