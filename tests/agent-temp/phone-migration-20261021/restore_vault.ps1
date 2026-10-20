param(
    [Parameter(Mandatory=$true)][string]$Device,
    [Parameter(Mandatory=$true)][string]$PreparedDirectory,
    [Parameter(Mandatory=$true)][string]$VerificationDirectory
)
$ErrorActionPreference = 'Stop'
$adb = 'C:\Users\18377\Android\Sdk\platform-tools\adb.exe'
$package = 'com.yuanfang.aitext.personal_ai_inbox'
function Invoke-Adb([string[]]$Arguments) {
    $output = & $adb -s $Device @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw ($output -join "`n") }
    return $output
}
Invoke-Adb @('shell','am','force-stop',$package) | Out-Null
Invoke-Adb @('shell','run-as',$package,'mkdir','-p','files/vault') | Out-Null
$existing = @(Invoke-Adb @('shell','run-as',$package,'find','files/vault','-type','f','-name','*.md'))
if (@($existing | Where-Object { $_.ToString().Trim() }).Count) {
    throw 'Refusing to restore into a vault that already contains Markdown files.'
}
$remoteArchive = '/data/local/tmp/lazy-secretary-restore-20261021.tar'
Invoke-Adb @('push',(Join-Path $PreparedDirectory 'restore-vault.tar'),$remoteArchive) | Out-Null
try {
    Invoke-Adb @('shell','run-as',$package,'tar','-xf',$remoteArchive,'-C','files/vault') | Out-Null
    $restored = @(Invoke-Adb @('shell','run-as',$package,'find','files/vault','-type','f','-name','*.md'))
    if ($restored.Count -ne 47) { throw 'Restored Markdown count is not 47.' }
    New-Item -ItemType Directory -Path $VerificationDirectory -Force | Out-Null
    $archivePath = Join-Path $VerificationDirectory 'vault-installed.tar'
    $processInfo = [Diagnostics.ProcessStartInfo]::new($adb)
    $processInfo.UseShellExecute = $false
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    foreach ($argument in @('-s',$Device,'exec-out','run-as',$package,'tar','-cf','-','-C','files/vault','vault')) {
        $processInfo.ArgumentList.Add($argument)
    }
    $process = [Diagnostics.Process]::Start($processInfo)
    $errors = $process.StandardError.ReadToEndAsync()
    $file = [IO.File]::Create($archivePath)
    try { $process.StandardOutput.BaseStream.CopyTo($file) } finally { $file.Dispose() }
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw $errors.Result }
    $process.Dispose()
    $entries = @(& tar.exe -tf $archivePath)
    if ($LASTEXITCODE -ne 0 -or @($entries | Where-Object { $_ -match '^/|\.\.' }).Count) {
        throw 'Invalid readback archive paths.'
    }
    $readback = Join-Path $VerificationDirectory 'readback'
    New-Item -ItemType Directory -Path $readback -Force | Out-Null
    & tar.exe -xf $archivePath -C $readback
    if ($LASTEXITCODE -ne 0) { throw 'Unable to extract readback archive.' }
    Write-Output "Restored 47 Markdown files; private-vault readback saved to $readback"
} finally {
    Invoke-Adb @('shell','rm','-f',$remoteArchive) | Out-Null
}
