param(
    [Parameter(Mandatory = $true)]
    [string]$FlutterExecutable
)

$ErrorActionPreference = 'Stop'
$expectedFlutterVersion = '3.47.6'
$expectedDartVersion = '3.13.5'

$machineOutput = & $FlutterExecutable --version --machine
if ($LASTEXITCODE -ne 0) {
    throw "Unable to query Flutter version from '$FlutterExecutable'."
}

try {
    $versionInfo = ($machineOutput -join "`n") | ConvertFrom-Json -ErrorAction Stop
}
catch {
    throw "Flutter returned an invalid machine version from '$FlutterExecutable'."
}

if ($versionInfo.frameworkVersion -ne $expectedFlutterVersion -or
    $versionInfo.dartSdkVersion -ne $expectedDartVersion) {
    throw "Expected Flutter $expectedFlutterVersion / Dart $expectedDartVersion; " +
        "found Flutter $($versionInfo.frameworkVersion) / Dart $($versionInfo.dartSdkVersion)."
}

Write-Verbose "Verified Flutter $expectedFlutterVersion / Dart $expectedDartVersion."
