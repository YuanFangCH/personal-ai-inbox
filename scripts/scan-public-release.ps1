[CmdletBinding()]
param(
    [switch]$CurrentTreeOnly,
    [switch]$AllRefs
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repoRoot

try {
    $trackedPaths = @(& git ls-files)
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to list tracked files.'
    }

    $forbiddenPathRules = @(
        @{ Name = 'environment file'; Pattern = '(^|/)\.env($|\.)' },
        @{ Name = 'signing or private key file'; Pattern = '\.(pem|key|p12|pfx|jks|keystore)$' },
        @{ Name = 'Android signing properties'; Pattern = '(^|/)key\.properties$' },
        @{ Name = 'local vault'; Pattern = '(^|/)vault/' },
        @{ Name = 'build output'; Pattern = '(^|/)(build|\.dart_tool)/' },
        @{ Name = 'local credential directory'; Pattern = '(^|/)(secrets?|credentials?)/' }
    )

    $pathFindings = [System.Collections.Generic.List[string]]::new()
    foreach ($path in $trackedPaths) {
        foreach ($rule in $forbiddenPathRules) {
            if ($path -match $rule.Pattern) {
                $pathFindings.Add("$($rule.Name): $path")
            }
        }
    }

    $secretPatterns = @(
        'sk-[A-Za-z0-9_-]{16,}',
        'gh[pousr]_[A-Za-z0-9]{20,}',
        'AIza[0-9A-Za-z_-]{30,}',
        'xox[baprs]-[A-Za-z0-9-]{20,}',
        'AKIA[0-9A-Z]{16}',
        'ASIA[0-9A-Z]{16}',
        '-----BEGIN [A-Z ]*PRIVATE KEY-----',
        'eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}',
        'Authorization:[[:space:]]*Bearer[[:space:]]+[A-Za-z0-9._~+/-]{20,}',
        '序列号[：:][[:space:]]*[A-Z0-9]{10,}',
        '-AndroidDevice[[:space:]]+[A-Z0-9]{10,}',
        '-d[[:space:]]+R[0-9A-Z]{10,}'
    )

    $grepArguments = @('-I', '-l', '-E')
    foreach ($pattern in $secretPatterns) {
        $grepArguments += @('-e', $pattern)
    }

    if ($CurrentTreeOnly) {
        $grepArguments += '--cached'
    } elseif ($AllRefs) {
        $grepArguments += @(& git rev-list --all)
    } else {
        $grepArguments += @(& git rev-list HEAD)
    }

    $secretMatches = @(& git grep @grepArguments)
    if ($LASTEXITCODE -gt 1) {
        throw 'Secret scan failed to execute.'
    }

    if ($pathFindings.Count -gt 0 -or $secretMatches.Count -gt 0) {
        $messages = [System.Collections.Generic.List[string]]::new()
        if ($pathFindings.Count -gt 0) {
            $messages.Add("Forbidden public-release paths:`n$($pathFindings -join "`n")")
        }
        if ($secretMatches.Count -gt 0) {
            $messages.Add("Potential secrets found in commits/files:`n$($secretMatches -join "`n")")
        }
        throw "Public release scan failed. No matching secret values were printed.`n$($messages -join "`n")"
    }

    Write-Output 'Public release scan passed.'
}
finally {
    Pop-Location
}
