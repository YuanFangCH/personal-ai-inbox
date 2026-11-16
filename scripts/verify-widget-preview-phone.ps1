param(
    [Parameter(Mandatory)][ValidateSet('Candidate','Published')][string]$Stage,
    [Parameter(Mandatory)][ValidateSet('Preflight','Start','Upgrade','Finish','Abort')][string]$Action,
    [ValidateSet('E','D')][string]$ValidationDrive='E',
    [string]$SdkRoot,
    [string]$AvdHome,
    [string]$OutputDir,
    [ValidateRange(30,600)][int]$BootTimeoutSeconds=180,
    [string]$EvidencePath
)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
. (Join-Path $PSScriptRoot 'lib\android-phone-validation.ps1')
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$app=Join-Path $repo 'app'
$version='1.6.2';$build=16;$tag='phone-v1.6.2';$package='com.yuanfang.aitext.personal_ai_inbox'
$certificate='51b5e2f3f44ce9374cb680a0173c6498a4e13c718c602a355a8b6a50523f4816'
$required=if($Stage -eq 'Candidate'){@('device.home-order','device.todo-order','device.widget-source-merge','device.widget-exclusions','device.widget-seven-day-boundary','device.widget-privacy','device.widget-2x2','device.widget-4x2','device.widget-large','device.widget-light','device.widget-dark','device.widget-large-font','device.widget-swipe','device.widget-page-taps','device.widget-resize-reset','device.widget-instance-isolation','device.widget-cold-click')}else{@('release.metadata','apk.current','apk.previous','upgrade.previous-install','upgrade.synthetic-state','upgrade.cover-install','upgrade.data-retained','upgrade.widget-binding','upgrade.widget-paging')}

function Set-ValidationPaths([string]$Drive){
    $script:ValidationDrive=$Drive
    if(-not $script:SdkRoot){$script:SdkRoot="$Drive`:\DevTools\Android\Sdk"}
    if(-not $script:AvdHome){$script:AvdHome="$Drive`:\DevTools\Android\.android\avd"}
    if(-not $script:OutputDir){$script:OutputDir="$Drive`:\DevTools\Android\aitext-validation\phone-v1.6.2"}
    $script:SdkRoot=Resolve-ValidationPath $script:SdkRoot 'SdkRoot' $Drive
    $script:AvdHome=Resolve-ValidationPath $script:AvdHome 'AvdHome' $Drive
    $script:OutputDir=Resolve-ValidationPath $script:OutputDir 'OutputDir' $Drive
    New-Item -ItemType Directory -Path $script:OutputDir -Force|Out-Null
    $script:sessionFile=Join-Path $script:OutputDir "$($Stage.ToLowerInvariant())-session.json"
    $script:resultFile=Join-Path $script:OutputDir "$($Stage.ToLowerInvariant())-result.json"
    $script:preflightFile=Join-Path $script:OutputDir 'preflight.json'
}

function Write-JsonAtomic([string]$Path,$Value){
    $tmp="$Path.tmp"
    $json=ConvertTo-Json -InputObject $Value -Depth 12
    [IO.File]::WriteAllText($tmp,$json,[Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Copy-AndroidSdkToD {
    $destination=Resolve-ValidationPath 'D:\DevTools\Android\Sdk' 'Fallback SDK' 'D'
    $required=@(
        (Join-Path $destination 'platform-tools\adb.exe'),
        (Join-Path $destination 'emulator\emulator.exe'),
        (Join-Path $destination 'system-images\android-35\google_apis\x86_64\system.img')
    )
    if(-not @($required|Where-Object{-not(Test-Path -LiteralPath $_ -PathType Leaf)}).Count){return $destination}
    $source=Resolve-ValidationPath 'E:\DevTools\Android\Sdk' 'Source SDK' 'E'
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force|Out-Null
    $copyLog='D:\DevTools\Android\aitext-validation\phone-v1.6.2\android-sdk-copy.log'
    & robocopy.exe $source $destination /E /COPY:DAT /DCOPY:DAT /R:0 /W:0 /XJ /XD .temp /NFL /NDL /NP "/LOG:$copyLog"|Out-Null
    if($LASTEXITCODE -ge 8){throw "Could not copy Android SDK from E: to D: (robocopy exit $LASTEXITCODE)."}
    $destination
}

function Invoke-StoragePreflight([string]$RequestedDrive){
    Set-ValidationPaths $RequestedDrive
    if($RequestedDrive -eq 'D' -and -not(Test-Path -LiteralPath $SdkRoot -PathType Container)){$script:SdkRoot=Copy-AndroidSdkToD;Set-ValidationPaths 'D'}
    try{$facts=Test-ValidationStorage -SdkRoot $SdkRoot -AvdHome $AvdHome -OutputDir $OutputDir -Drive $RequestedDrive}
    catch{
        $io=$_.Exception -is [IO.IOException] -or $_.Exception.InnerException -is [IO.IOException] -or $_.Exception.Message -match '(?i)I/O|不存在的设备|device.*not.*exist|failed to flush'
        if($RequestedDrive -ne 'E' -or -not $io){throw}
        $sourceFailure=$_.Exception.Message
        $dSdk=Copy-AndroidSdkToD
        $script:SdkRoot=$dSdk;$script:AvdHome='D:\DevTools\Android\.android\avd';$script:OutputDir='D:\DevTools\Android\aitext-validation\phone-v1.6.2'
        Set-ValidationPaths 'D'
        $facts=Test-ValidationStorage -SdkRoot $SdkRoot -AvdHome $AvdHome -OutputDir $OutputDir -Drive D
        $facts|Add-Member NoteProperty fallbackFromDrive E
        $facts|Add-Member NoteProperty fallbackReason $sourceFailure
    }
    $preflight=[pscustomobject]@{status='passed';stage=$Stage;createdAt=[datetime]::UtcNow.ToString('o');storage=$facts;sdkRoot=$SdkRoot;avdHome=$AvdHome;outputDir=$OutputDir}
    Write-JsonAtomic $preflightFile $preflight
    $preflight
}

function Assert-Preflight {
    if(-not(Test-Path -LiteralPath $preflightFile -PathType Leaf)){throw "Run -Action Preflight first: $preflightFile"}
    $pf=Get-Content -LiteralPath $preflightFile -Raw|ConvertFrom-Json
    if($pf.status -ne 'passed'){throw "The saved storage preflight did not pass: $preflightFile"}
    if($pf.storage.drive -ne $ValidationDrive){throw "Preflight selected drive $($pf.storage.drive); rerun this command with -ValidationDrive $($pf.storage.drive)."}
    $pf
}

function Get-MachineCheck([string]$Id,[string]$Detail,[string[]]$Artifacts=@()){
    [pscustomobject]@{id=$Id;status='passed';detail=$Detail;artifacts=$Artifacts}
}

function Invoke-NativeWithLog([string]$FilePath,[string[]]$Arguments,[string]$LogPath){
    $oldPreference=$ErrorActionPreference
    try{
        $ErrorActionPreference='Continue'
        & $FilePath @Arguments *> $LogPath
        return $LASTEXITCODE
    }finally{$ErrorActionPreference=$oldPreference}
}

function Ensure-DebugKeystore([string]$Drive){
    $path=Resolve-ValidationPath "$Drive`:\DevTools\Android\.android\debug.keystore" 'Debug keystore' $Drive
    if(Test-Path -LiteralPath $path -PathType Leaf){return $path}
    $javac=(Get-Command javac.exe -ErrorAction Stop).Source
    $keytool=Join-Path (Split-Path -Parent $javac) 'keytool.exe'
    if(-not(Test-Path -LiteralPath $keytool -PathType Leaf)){throw "keytool is missing next to javac: $javac"}
    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force|Out-Null
    & $keytool -genkeypair -keystore $path -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname 'CN=Android Debug,O=Android,C=US' *> (Join-Path $OutputDir 'candidate-debug-keystore.log')
    if($LASTEXITCODE -ne 0 -or -not(Test-Path -LiteralPath $path -PathType Leaf)){throw 'Could not create the validation debug keystore.'}
    $path
}

function Save-Result([string]$Status,[bool]$Aborted,$Checks,$Session){
    $result=[pscustomobject]@{stage=$Stage;status=$Status;aborted=$Aborted;sessionId=$Session.sessionId;drive=$Session.drive;version=$version;buildNumber=$build;avdName=$Session.avdName;deviceSerial=$Session.serial;artifactSha256=$Session.artifactSha256;checks=@($Checks)}
    Write-JsonAtomic $resultFile $result
    $result
}

function Complete-Run([bool]$Aborted){
    $session=$null;$checks=[Collections.Generic.List[object]]::new();$failure=$null
    try{
        if(Test-Path -LiteralPath $sessionFile){$session=Get-Content -LiteralPath $sessionFile -Raw|ConvertFrom-Json}
        if(-not $session){throw 'No matching validation session exists.'}
        foreach($item in @($session.machineChecks)){$checks.Add($item)}
        $storageErrors=@(Test-NewValidationStorageEvents -EventBaseline $session.storage.eventBaseline -Drive $ValidationDrive -DiskNumber $session.storage.diskNumber)
        if($storageErrors.Count){$checks.Add([pscustomobject]@{id='environment.storage-events';status='failed';detail='New E/D volume or physical disk I/O events occurred during this session.';artifacts=@()})}
        if($EvidencePath -and (Test-Path -LiteralPath $EvidencePath -PathType Leaf)){
            $e=Get-Content -LiteralPath $EvidencePath -Raw -Encoding UTF8|ConvertFrom-Json
            if($e.sessionId -ne $session.sessionId){throw 'Evidence sessionId does not match the active session.'}
            foreach($item in @($e.checks)){if($item.id -in @($checks | ForEach-Object id) -or $item.id -eq 'upgrade.cover-install'){throw "Evidence cannot supply a machine check: $($item.id)"};$checks.Add($item)}
        }elseif(-not $Aborted){throw 'Finish requires an evidence JSON file.'}
        foreach($id in $required){$matching=@($checks|Where-Object id -eq $id);if($matching.Count -ne 1){$checks.Add([pscustomobject]@{id=$id;status='failed';detail='Required evidence missing or duplicate.';artifacts=@()})}elseif(@($matching[0].artifacts).Count -eq 0){$matching[0].status='failed';$matching[0].detail='Required evidence has no artifacts.'}}
        $root=(Resolve-ValidationPath $OutputDir 'OutputDir' $ValidationDrive).TrimEnd('\')+'\'
        foreach($item in $checks){if($item.status -notin @('passed','failed','skipped')){$item.status='failed'};foreach($artifact in @($item.artifacts)){$relative=[string]$artifact;if([IO.Path]::IsPathRooted($relative)){throw 'Evidence artifact paths must be relative to OutputDir.'};$path=[IO.Path]::GetFullPath((Join-Path $OutputDir $relative));if(-not $path.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){throw 'Evidence artifact path escapes OutputDir.'};Resolve-ValidationPath $path 'Evidence artifact' $ValidationDrive|Out-Null;if(-not(Test-Path -LiteralPath $path -PathType Leaf)){$item.status='failed'}}}
        if($Aborted){$checks.Add([pscustomobject]@{id='run.aborted';status='skipped';detail='Run explicitly aborted.';artifacts=@()})}
    }catch{$failure=$_.Exception.Message;$checks.Add([pscustomobject]@{id='run.failure';status='failed';detail=$failure;artifacts=@()})}
    $bad=$Aborted -or $null -ne $failure -or @($checks|Where-Object status -ne 'passed').Count -gt 0
    $result=Save-Result $(if($bad){'failed'}else{'passed'}) $Aborted $checks $session
    if($session){try{Stop-PhoneAvd -Session $session -SdkRoot $SdkRoot}catch{$result.checks+=,[pscustomobject]@{id='environment.cleanup';status='failed';detail=$_.Exception.Message;artifacts=@()};$result.status='failed';Write-JsonAtomic $resultFile $result}}
    if(Test-Path -LiteralPath $sessionFile){Remove-Item -LiteralPath $sessionFile -Force}
    if($result.status -ne 'passed' -and (-not $Aborted -or $result.checks.id -contains 'environment.cleanup' -or $failure)){throw "Validation did not pass; see $resultFile"}
    $result
}

Set-ValidationPaths $ValidationDrive
try {
    $result = switch($Action){
    Preflight { Invoke-StoragePreflight $ValidationDrive }
    Start {
        $pf=Assert-Preflight
        if($pf.storage.drive -ne $ValidationDrive){throw "Use -ValidationDrive $($pf.storage.drive) from the preflight result."}
        if(Test-Path -LiteralPath $sessionFile){throw "An active $Stage session already exists: $sessionFile"}
        $storageErrors=Test-NewValidationStorageEvents -EventBaseline $pf.storage.eventBaseline -Drive $ValidationDrive -DiskNumber $pf.storage.diskNumber
        if($storageErrors.Count){throw 'New disk or NTFS I/O errors occurred after preflight; switch to the other validation drive.'}
        $machine=[Collections.Generic.List[object]]::new();$avdName=if($Stage -eq 'Candidate'){'aitext_v162_candidate_phone'}else{'aitext_v162_upgrade_phone'}
        if($Stage -eq 'Candidate'){
            $flutter='D:\Flutter-recovery-3.47.6\sdk\flutter\bin\flutter.bat';if(-not(Test-Path -LiteralPath $flutter)){throw 'Flutter 3.47.6 was not found.'}
            $debugKeystore=Ensure-DebugKeystore $ValidationDrive
            $oldSdk=$env:ANDROID_SDK_ROOT;$oldHome=$env:ANDROID_HOME;$oldGradle=$env:GRADLE_USER_HOME;$oldAndroidUserHome=$env:ANDROID_USER_HOME;$oldDebugKeystore=$env:AITEXT_DEBUG_KEYSTORE_PATH;$oldLocal=Get-Content -LiteralPath (Join-Path $app 'android\local.properties') -Raw
            $windowsTestGate=Join-Path $app '.dart_tool\aitext_skip_windows_pdfium_gate'
            try{
                $env:ANDROID_SDK_ROOT=$SdkRoot;$env:ANDROID_HOME=$SdkRoot
                $env:ANDROID_USER_HOME=(Split-Path -Parent $AvdHome)
                $env:AITEXT_DEBUG_KEYSTORE_PATH=$debugKeystore
                $env:GRADLE_USER_HOME=if($ValidationDrive -eq 'D'){'D:\GradleCache'}else{'E:\DevTools\Gradle\.gradle'}
                $localPath=Join-Path $app 'android\local.properties';$sdkLine='sdk.dir='+$SdkRoot.Replace('\','\\')
                if($oldLocal -match '(?m)^sdk\.dir=.*$'){$newLocal=[regex]::Replace($oldLocal,'(?m)^sdk\.dir=.*$',[System.Text.RegularExpressions.MatchEvaluator]{param($m)$sdkLine})}else{$newLocal=$oldLocal+"`nsdk.dir=$($SdkRoot.Replace('\','\\'))`n"}
                [IO.File]::WriteAllText($localPath,$newLocal,[Text.UTF8Encoding]::new($false))
                Push-Location $app
                try{
                    New-Item -ItemType File -Path $windowsTestGate -Force|Out-Null
                    if(-not(Test-Path -LiteralPath (Join-Path $app '.dart_tool\package_config.json') -PathType Leaf)){
                        $exitCode=Invoke-NativeWithLog $flutter @('pub','get') (Join-Path $OutputDir 'candidate-pub-get.log')
                        if($exitCode -ne 0){throw 'Flutter package resolution failed.'}
                    }
                    $testLog=Join-Path $OutputDir 'candidate-targeted-tests.log'
                    $exitCode=Invoke-NativeWithLog $flutter @('test','--no-pub','--reporter','expanded','test/home_page_ui_test.dart','test/home_widgets/home_widget_projection_test.dart','test/home_widgets/home_widget_contract_test.dart','test/home_widgets/widget_workspace_test.dart','test/home_widgets/widget_store_test.dart','test/home_widget_bridge_test.dart','test/widget_tools_test.dart') $testLog
                    if($exitCode -ne 0){throw 'Widget/home/table-detail targeted tests failed.'}
                    $exitCode=Invoke-NativeWithLog $flutter @('test','--no-pub','--reporter','expanded','test/tables_page_test.dart','--plain-name','table detail sorts dated entries before entries without time') (Join-Path $OutputDir 'table-detail-targeted-test.log')
                    if($exitCode -ne 0){throw 'Table-detail chronological order UI test failed.'}
                    $machine.Add((Get-MachineCheck 'host.targeted-tests' 'Home, table detail, widget projection/configuration, bridge and secretary tool tests passed.'))
                    Remove-Item -LiteralPath $windowsTestGate -Force
                    $exitCode=Invoke-NativeWithLog $flutter @('build','apk','--debug','--no-pub') (Join-Path $OutputDir 'candidate-build.log')
                    if($exitCode -ne 0){throw 'Debug APK build failed.'}
                }finally{Pop-Location}
            }finally{
                [IO.File]::WriteAllText((Join-Path $app 'android\local.properties'),$oldLocal,[Text.UTF8Encoding]::new($false))
                if($null -eq $oldSdk){Remove-Item Env:ANDROID_SDK_ROOT -ErrorAction SilentlyContinue}else{$env:ANDROID_SDK_ROOT=$oldSdk}
                if($null -eq $oldHome){Remove-Item Env:ANDROID_HOME -ErrorAction SilentlyContinue}else{$env:ANDROID_HOME=$oldHome}
                if($null -eq $oldGradle){Remove-Item Env:GRADLE_USER_HOME -ErrorAction SilentlyContinue}else{$env:GRADLE_USER_HOME=$oldGradle}
                if($null -eq $oldAndroidUserHome){Remove-Item Env:ANDROID_USER_HOME -ErrorAction SilentlyContinue}else{$env:ANDROID_USER_HOME=$oldAndroidUserHome}
                if($null -eq $oldDebugKeystore){Remove-Item Env:AITEXT_DEBUG_KEYSTORE_PATH -ErrorAction SilentlyContinue}else{$env:AITEXT_DEBUG_KEYSTORE_PATH=$oldDebugKeystore}
                if(Test-Path -LiteralPath $windowsTestGate){Remove-Item -LiteralPath $windowsTestGate -Force}
            }
            $apk=Join-Path $app 'build\app\outputs\flutter-apk\app-debug.apk';$facts=Get-PhoneApkFacts -ApkPath $apk -SdkRoot $SdkRoot
            if($facts.packageName -ne $package -or $facts.versionName -ne $version -or $facts.versionCode -ne $build -or -not $facts.debuggable){throw 'Candidate APK must be the expected debuggable 1.6.2+16 package.'}
            $dest=Join-Path $OutputDir 'candidate-app-debug.apk';Copy-Item -LiteralPath $apk -Destination $dest -Force;$facts=Get-PhoneApkFacts -ApkPath $dest -SdkRoot $SdkRoot
            $artifactHash=$facts.sha256;$machine.Add((Get-MachineCheck 'apk.candidate' "sha256=$artifactHash; package=$($facts.packageName); version=$version+$build; min/target SDK=$($facts.minSdk)/$($facts.targetSdk); debuggable=$($facts.debuggable)" @('candidate-app-debug.apk')))
        }else{
            $release=gh release view $tag --repo YuanFangCH/personal-ai-inbox --json tagName,isPrerelease,isDraft,assets 2> (Join-Path $OutputDir 'release-metadata.log')|ConvertFrom-Json
            if($LASTEXITCODE -ne 0 -or $release.tagName -ne $tag -or -not $release.isPrerelease -or $release.isDraft){throw 'GitHub release must be the public non-draft v1.6.2 pre-release.'}
            $names=@($release.assets|ForEach-Object name);if(($names|Sort-Object) -join ',' -ne 'SHA256SUMS.txt,personal-ai-inbox-v1.6.2-android.apk'){throw 'Unexpected public release assets.'}
            $published=Join-Path $OutputDir 'published';New-Item -ItemType Directory $published -Force|Out-Null
            gh release download $tag --repo YuanFangCH/personal-ai-inbox --pattern 'personal-ai-inbox-v1.6.2-android.apk' --pattern SHA256SUMS.txt --dir $published --clobber *> (Join-Path $OutputDir 'published-assets-download.log');if($LASTEXITCODE -ne 0){throw 'Unable to download public v1.6.2 assets.'}
            $apk=Join-Path $published 'personal-ai-inbox-v1.6.2-android.apk';$currentFacts=Test-PhoneApk -ApkPath $apk -ChecksumsPath (Join-Path $published 'SHA256SUMS.txt') -SdkRoot $SdkRoot -Version $version -Build $build -CertificateSha256 $certificate
            $artifactHash=$currentFacts.sha256;$machine.Add((Get-MachineCheck 'release.metadata' 'Public non-draft pre-release and expected assets verified.' @('published\SHA256SUMS.txt')));$machine.Add((Get-MachineCheck 'apk.current' "sha256=$artifactHash; v2 signature and long-term certificate verified." @('published\personal-ai-inbox-v1.6.2-android.apk')))
            $oldDir=Join-Path $OutputDir 'previous';New-Item -ItemType Directory $oldDir -Force|Out-Null
            gh release download phone-v1.6.1 --repo YuanFangCH/personal-ai-inbox --pattern 'personal-ai-inbox-v1.6.1-android.apk' --pattern SHA256SUMS.txt --dir $oldDir --clobber *> (Join-Path $OutputDir 'previous-assets-download.log');if($LASTEXITCODE -ne 0){throw 'Unable to download v1.6.1 public APK.'}
            $oldApk=Join-Path $oldDir 'personal-ai-inbox-v1.6.1-android.apk';$previousFacts=Test-PhoneApk -ApkPath $oldApk -ChecksumsPath (Join-Path $oldDir 'SHA256SUMS.txt') -SdkRoot $SdkRoot -Version '1.6.1' -Build 15 -CertificateSha256 $certificate
            $machine.Add((Get-MachineCheck 'apk.previous' "sha256=$($previousFacts.sha256); v1.6.1+15 verified." @('previous\personal-ai-inbox-v1.6.1-android.apk')))
        }
        $session=$null
        try{
            $session=Start-PhoneAvd -SdkRoot $SdkRoot -AvdHome $AvdHome -AvdName $avdName -OutputDir $OutputDir -BootTimeoutSeconds $BootTimeoutSeconds -ValidationDrive $ValidationDrive
            $machine.Add((Get-MachineCheck 'environment.avd-boot' "serial=$($session.serial); API=$($session.apiLevel); drive=$($session.drive)"))
            Wait-PhoneAdbOnline -Serial $session.serial -SdkRoot $SdkRoot
            if($Stage -eq 'Published'){
                $adb=Join-Path $SdkRoot 'platform-tools\adb.exe'
                $exitCode=Invoke-NativeWithLog $adb @('-s',$session.serial,'install',$oldApk) (Join-Path $OutputDir 'previous-install.log')
                if($exitCode -ne 0){throw 'Could not install public v1.6.1 APK.'}
                Assert-InstalledVersion -Serial $session.serial -PackageName $package -ExpectedVersion '1.6.1' -ExpectedBuild 15 -SdkRoot $SdkRoot
                $machine.Add((Get-MachineCheck 'upgrade.previous-install' 'Public v1.6.1+15 installed and package version verified.' @('previous\personal-ai-inbox-v1.6.1-android.apk')))
            }else{
                $adb=Join-Path $SdkRoot 'platform-tools\adb.exe'
                $exitCode=Invoke-NativeWithLog $adb @('-s',$session.serial,'install','-r',$dest) (Join-Path $OutputDir 'candidate-install.log')
                if($exitCode -ne 0){throw 'Could not install candidate APK.'}
                Assert-InstalledVersion -Serial $session.serial -PackageName $package -ExpectedVersion $version -ExpectedBuild $build -SdkRoot $SdkRoot
                $machine.Add((Get-MachineCheck 'install.candidate' 'Candidate 1.6.2+16 installed and package version verified.'))
            }
            $session|Add-Member NoteProperty sessionId ([guid]::NewGuid().ToString('D')) -Force
            $session|Add-Member NoteProperty stage $Stage -Force;$session|Add-Member NoteProperty outputDir $OutputDir -Force;$session|Add-Member NoteProperty installedVersion $(if($Stage -eq 'Candidate'){$version}else{'1.6.1'}) -Force;$session|Add-Member NoteProperty installedBuildNumber $(if($Stage -eq 'Candidate'){$build}else{15}) -Force
            $session|Add-Member NoteProperty artifactSha256 $artifactHash -Force;$session|Add-Member NoteProperty startedAt ([datetime]::UtcNow.ToString('o')) -Force;$session|Add-Member NoteProperty upgraded $false -Force;$session|Add-Member NoteProperty machineChecks @($machine) -Force;$session|Add-Member NoteProperty storage $pf.storage -Force
            if($Stage -eq 'Published'){$session|Add-Member NoteProperty CurrentApk $apk -Force;$session|Add-Member NoteProperty PreviousInstalled $true -Force;$session|Add-Member NoteProperty PreviousApkSha256 $previousFacts.sha256 -Force}
            Write-JsonAtomic $sessionFile $session;$session
        }catch{if($session){Stop-PhoneAvd -Session $session -SdkRoot $SdkRoot};throw}
    }
    Upgrade {
        if($Stage -ne 'Published'){throw 'Upgrade is only valid for Published stage.'}
        if(-not(Test-Path -LiteralPath $sessionFile)){throw 'Published Start must complete before Upgrade.'}
        $session=Get-Content -LiteralPath $sessionFile -Raw|ConvertFrom-Json
        if(-not $EvidencePath -or -not(Test-Path -LiteralPath $EvidencePath -PathType Leaf)){throw 'EvidencePath must contain pre-upgrade synthetic-state and widget-binding evidence.'}
        $e=Get-Content -LiteralPath $EvidencePath -Raw -Encoding UTF8|ConvertFrom-Json
        if($e.sessionId -ne $session.sessionId){throw 'Evidence sessionId does not match the active upgrade AVD.'}
        foreach($id in @('upgrade.synthetic-state','upgrade.widget-binding')){$items=@($e.checks|Where-Object id -eq $id);if($items.Count -ne 1 -or $items[0].status -ne 'passed' -or @($items[0].artifacts).Count -eq 0){throw "A unique passed $id item with evidence is required before overwrite."};foreach($a in $items[0].artifacts){$p=[IO.Path]::GetFullPath((Join-Path $OutputDir ([string]$a)));if(-not $p.StartsWith(((Resolve-ValidationPath $OutputDir 'OutputDir' $ValidationDrive).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase) -or -not(Test-Path -LiteralPath $p -PathType Leaf)){throw "Invalid upgrade evidence artifact: $a"}}}
        $sdkHash=(Get-FileHash -LiteralPath $session.CurrentApk -Algorithm SHA256).Hash.ToLowerInvariant();if($sdkHash -ne $session.artifactSha256){throw 'Published v1.6.2 APK hash changed after session start.'}
        $adb=Join-Path $SdkRoot 'platform-tools\adb.exe'
        $exitCode=Invoke-NativeWithLog $adb @('-s',$session.serial,'install','-r',$session.CurrentApk) (Join-Path $OutputDir 'published-upgrade-install.log')
        if($exitCode -ne 0){throw 'Public v1.6.2 overwrite installation failed.'}
        Assert-InstalledVersion -Serial $session.serial -PackageName $package -ExpectedVersion $version -ExpectedBuild $build -SdkRoot $SdkRoot
        $session.installedVersion=$version;$session.installedBuildNumber=$build;$session.upgraded=$true;$session.machineChecks+=Get-MachineCheck 'upgrade.cover-install' 'Public APK installed with adb install -r; package version verified.' @('published-upgrade-install.log');Write-JsonAtomic $sessionFile $session;$session
    }
    Finish { Complete-Run $false }
    Abort { Complete-Run $true }
    }
    [Console]::Out.WriteLine((ConvertTo-Json -InputObject $result -Depth 20 -Compress))
} catch {
    $errorDetail=($_|Out-String)
    if($OutputDir){try{[IO.File]::WriteAllText((Join-Path $OutputDir 'script-error.log'),$errorDetail,[Text.UTF8Encoding]::new($false))}catch{}}
    [Console]::Out.WriteLine((ConvertTo-Json -InputObject ([pscustomobject]@{
        stage=$Stage
        action=$Action
        status='failed'
        error="$($_.Exception.Message) (line $($_.InvocationInfo.ScriptLineNumber))"
    }) -Depth 5 -Compress))
    exit 1
}
