function Resolve-ValidationPath {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Label,[Parameter(Mandatory)][ValidateSet('E','D')][string]$Drive)
    if(-not [IO.Path]::IsPathRooted($Path)){throw "$Label must be absolute: $Path"}
    $full=[IO.Path]::GetFullPath($Path)
    if([IO.Path]::GetPathRoot($full) -ne "$Drive`:\"){throw "$Label must resolve on $Drive`:\: $full"}
    $cursor=$full
    while($cursor){
        $item=Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
        if($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){
            try{$target=(Resolve-Path -LiteralPath $cursor -ErrorAction Stop).Path}catch{throw "$Label has an unresolved link: $cursor"}
            if([IO.Path]::GetPathRoot([IO.Path]::GetFullPath($target)) -ne "$Drive`:\"){throw "$Label escapes $Drive`:\ through $cursor -> $target"}
        }
        $parent=Split-Path -Parent $cursor
        if(-not $parent -or $parent -eq $cursor){break}
        $cursor=$parent
    }
    $full.TrimEnd('\')
}

function Resolve-AbsoluteEPath {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Label)
    Resolve-ValidationPath -Path $Path -Label $Label -Drive E
}

function Invoke-AdbText {
    param([Parameter(Mandatory)][string]$Adb,[string[]]$Arguments=@())
    $oldPreference=$ErrorActionPreference
    try{
        $ErrorActionPreference='Continue'
        $output=@(& $Adb @Arguments 2>&1)
        [pscustomobject]@{exitCode=$LASTEXITCODE;text=($output|ForEach-Object{[string]$_}) -join "`n"}
    }finally{$ErrorActionPreference=$oldPreference}
}

function Get-PhoneStorageEvents {
    param([datetime]$Since,[char]$Drive,[int]$DiskNumber)
    $events=Get-WinEvent -FilterHashtable @{LogName='System';StartTime=$Since.ToLocalTime();Id=7,11,15,51,55,57,129,140,153,157} -MaxEvents 2048 -ErrorAction SilentlyContinue
    @($events|Where-Object{$_.TimeCreated.ToUniversalTime() -ge $Since}|Where-Object{
        $message=$_.Message
        ($_.ProviderName -match 'Ntfs|vol' -and $message -match "(?i)(VolumeId:\s*$Drive`:|Volume\s+$Drive`:)" ) -or
        ($_.ProviderName -match 'disk|stor|Ntfs' -and ($message -match "(?i)Harddisk$DiskNumber(?:\\|\b)" -or $message -match "(?i)Harddisk$DiskNumber\b"))
    }|ForEach-Object{[pscustomobject]@{time=$_.TimeCreated.ToUniversalTime().ToString('o');id=$_.Id;provider=$_.ProviderName;message=(($_.Message -split "`r?`n")[0])}})
}

function Get-FileReadProbe {
    param([Parameter(Mandatory)][string]$Path)
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    try{
        $length=$stream.Length
        $positions=@([long]0,[long][math]::Floor($length/2),[long][math]::Max([long]0,$length-[long]1))|Select-Object -Unique
        foreach($position in $positions){$stream.Position=$position;if($stream.ReadByte() -lt 0){throw [IO.IOException]::new("Unable to read $Path at offset $position")}}
        [pscustomobject]@{path=$Path;length=$length}
    }finally{$stream.Dispose()}
}

function Test-ValidationStorage {
    param([Parameter(Mandatory)][string]$SdkRoot,[Parameter(Mandatory)][string]$AvdHome,[Parameter(Mandatory)][string]$OutputDir,[Parameter(Mandatory)][ValidateSet('E','D')][string]$Drive,[int]$ProbeBytes=268435456)
    $sdk=Resolve-ValidationPath $SdkRoot 'SdkRoot' $Drive
    $avds=Resolve-ValidationPath $AvdHome 'AvdHome' $Drive
    $output=Resolve-ValidationPath $OutputDir 'OutputDir' $Drive
    New-Item -ItemType Directory -Path $output -Force|Out-Null
    $partition=Get-Partition -DriveLetter $Drive -ErrorAction Stop
    $diskNumber=[int]$partition.DiskNumber
    $systemImage=Join-Path $sdk 'system-images\android-35\google_apis\x86_64'
    $paths=@((Join-Path $sdk 'platform-tools\adb.exe'),(Join-Path $sdk 'emulator\emulator.exe'),(Join-Path $sdk 'ndk\28.2.13676358\meta\abis.json'),(Join-Path $systemImage 'system.img'),(Join-Path $systemImage 'kernel-ranchu'))
    $gradleRoot="$Drive`:\DevTools\Gradle\.gradle\wrapper\dists\gradle-9.3.1-all"
    $gradleJar=Get-ChildItem $gradleRoot -Filter gradle-gradle-cli-9.3.1.jar -Recurse -ErrorAction SilentlyContinue|Select-Object -First 1 -ExpandProperty FullName
    if($gradleJar){$paths+=,$gradleJar}
    foreach($avdName in @('aitext_v162_candidate_phone','aitext_v162_upgrade_phone')){
        $ini=Join-Path $avds "$avdName.ini"
        if(Test-Path -LiteralPath $ini){
            try{$avdPath=(Select-String -LiteralPath $ini -Pattern '^path=' -ErrorAction Stop|Select-Object -First 1).Line.Substring(5)}catch{throw [IO.IOException]::new("Cannot read AVD locator $ini",$_.Exception)}
            $resolvedAvd=Resolve-ValidationPath $avdPath "$avdName data" $Drive
            $config=Join-Path $resolvedAvd 'config.ini'
            try{$configText=[IO.File]::ReadAllText($config)}catch{throw [IO.IOException]::new("Cannot read AVD config $config",$_.Exception)}
            if($configText -notmatch '(?m)^image\.sysdir\.1\s*=\s*system-images[\\/]android-35[\\/]google_apis[\\/]x86_64[\\/]?\s*$'){throw "AVD $avdName is not configured for Android 15 / API 35: $config"}
            $paths+=,$config
        }
    }
    $checked=[Collections.Generic.List[object]]::new()
    foreach($path in $paths){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Required Android SDK file is missing: $path"};$checked.Add((Get-FileReadProbe $path))}
    $since=[datetime]::UtcNow
    $probePath=Join-Path $output ('.phone-storage-probe-'+[guid]::NewGuid().ToString('N')+'.bin')
    $buffer=New-Object byte[] (1MB)
    $rng=[Security.Cryptography.RandomNumberGenerator]::Create()
    $writerHash=[Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)
    $readerHash=[Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)
    try{
        $stream=[IO.FileStream]::new($probePath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None,1MB,[IO.FileOptions]::WriteThrough)
        try{$remaining=$ProbeBytes;while($remaining -gt 0){$count=[math]::Min($buffer.Length,$remaining);$rng.GetBytes($buffer);$stream.Write($buffer,0,$count);$writerHash.AppendData($buffer,0,$count);$remaining-=$count};$stream.Flush($true)}finally{$stream.Dispose()}
        $writeHash=([BitConverter]::ToString($writerHash.GetHashAndReset()) -replace '-','').ToLowerInvariant()
        $stream=[IO.File]::OpenRead($probePath)
        try{while(($count=$stream.Read($buffer,0,$buffer.Length)) -gt 0){$readerHash.AppendData($buffer,0,$count)}}finally{$stream.Dispose()}
        $readHash=([BitConverter]::ToString($readerHash.GetHashAndReset()) -replace '-','').ToLowerInvariant()
        if($readHash -ne $writeHash){throw [IO.IOException]::new("Storage preflight SHA-256 mismatch for $Drive`:\")}
        $newEvents=@(Get-PhoneStorageEvents -Since $since -Drive $Drive -DiskNumber $diskNumber)
        if($newEvents.Count){throw [IO.IOException]::new("New NTFS/disk I/O events occurred during storage preflight on $Drive`:.")}
    }catch{if($_.Exception -is [IO.IOException] -or $_.Exception.InnerException -is [IO.IOException]){throw [IO.IOException]::new("Storage preflight failed on $Drive`:\: $($_.Exception.Message)",$_.Exception)};throw}
    finally{
        $rng.Dispose();$writerHash.Dispose();$readerHash.Dispose()
        if(Test-Path -LiteralPath $probePath){Remove-Item -LiteralPath $probePath -Force -ErrorAction Stop}
    }
    [pscustomobject]@{drive=$Drive;diskNumber=$diskNumber;probeBytes=$ProbeBytes;probeSha256=$writeHash;eventBaseline=$since.ToString('o');checkedPaths=@($checked)}
}

function Test-NewValidationStorageEvents {
    param([Parameter(Mandatory)][string]$EventBaseline,[Parameter(Mandatory)][ValidateSet('E','D')][string]$Drive,[Parameter(Mandatory)][int]$DiskNumber)
    $since=[datetime]::Parse($EventBaseline).ToUniversalTime()
    Get-PhoneStorageEvents -Since $since -Drive $Drive -DiskNumber $DiskNumber
}

function Start-PhoneAvd {
    param([Parameter(Mandatory)][string]$SdkRoot,[Parameter(Mandatory)][string]$AvdHome,[Parameter(Mandatory)][string]$AvdName,[Parameter(Mandatory)][string]$OutputDir,[ValidateRange(30,600)][int]$BootTimeoutSeconds=180,[ValidateSet('E','D')][string]$ValidationDrive='E')
    $SdkRoot=Resolve-ValidationPath $SdkRoot 'SdkRoot' $ValidationDrive
    $AvdHome=Resolve-ValidationPath $AvdHome 'AvdHome' $ValidationDrive
    $OutputDir=Resolve-ValidationPath $OutputDir 'OutputDir' $ValidationDrive
    $adb=Join-Path $SdkRoot 'platform-tools\adb.exe';$emulator=Join-Path $SdkRoot 'emulator\emulator.exe'
    if(-not(Test-Path -LiteralPath $adb -PathType Leaf) -or -not(Test-Path -LiteralPath $emulator -PathType Leaf)){throw "Android SDK binaries are missing on $ValidationDrive`:."}
    $ini=Join-Path $AvdHome "$AvdName.ini"
    if(-not(Test-Path -LiteralPath $ini -PathType Leaf)){
        $manager=Join-Path $SdkRoot 'cmdline-tools\latest\bin\avdmanager.bat'
        if(-not(Test-Path -LiteralPath $manager -PathType Leaf)){throw 'avdmanager is required to create the isolated API 35 phone AVD.'}
        $newPath=Resolve-ValidationPath (Join-Path $AvdHome "$AvdName.avd") 'New AVD data path' $ValidationDrive
        $psi=[Diagnostics.ProcessStartInfo]::new();$psi.FileName=$manager
        $psi.Arguments="create avd --force --name $AvdName --package system-images;android-35;google_apis;x86_64 --device pixel_6 --path `"$newPath`""
        $psi.UseShellExecute=$false;$psi.RedirectStandardInput=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
        $oldManagerEnv=@{};foreach($name in @('ANDROID_AVD_HOME','ANDROID_HOME','ANDROID_SDK_ROOT')){$oldManagerEnv[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
        try{[Environment]::SetEnvironmentVariable('ANDROID_AVD_HOME',$AvdHome,'Process');[Environment]::SetEnvironmentVariable('ANDROID_HOME',$SdkRoot,'Process');[Environment]::SetEnvironmentVariable('ANDROID_SDK_ROOT',$SdkRoot,'Process');$creator=[Diagnostics.Process]::Start($psi);$creator.StandardInput.WriteLine('no');$creator.StandardInput.Close();$createOut=$creator.StandardOutput.ReadToEnd();$createErr=$creator.StandardError.ReadToEnd();$creator.WaitForExit();if($creator.ExitCode -ne 0 -or -not(Test-Path -LiteralPath $ini)){throw "Unable to create isolated AVD. $createOut $createErr"}}finally{foreach($name in $oldManagerEnv.Keys){[Environment]::SetEnvironmentVariable($name,$oldManagerEnv[$name],'Process')}}
    }
    $avdPath=(Select-String -LiteralPath $ini -Pattern '^path=' -ErrorAction Stop|Select-Object -First 1).Line.Substring(5)
    $avdPath=Resolve-ValidationPath $avdPath 'AVD data path' $ValidationDrive
    $config=Join-Path $avdPath 'config.ini'
    try{$configText=[IO.File]::ReadAllText($config)}catch{throw "Cannot read AVD config on $ValidationDrive`:: $config. $($_.Exception.Message)"}
    if($configText -notmatch '(?m)^image\.sysdir\.1\s*=\s*system-images[\\/]android-35[\\/]google_apis[\\/]x86_64[\\/]?\s*$'){throw "AVD must use Android 15 / API 35: $config"}
    $imageRef='system-images/android-35/google_apis/x86_64'
    $imagePath=Resolve-ValidationPath (Join-Path $SdkRoot $imageRef) 'Android system image' $ValidationDrive
    if(-not(Test-Path -LiteralPath $imagePath -PathType Container)){throw "Android system image is missing: $imagePath"}
    if(Get-CimInstance Win32_Process|Where-Object{$_.Name -in @('emulator.exe','qemu-system-x86_64-headless.exe') -and $_.CommandLine -match [regex]::Escape($AvdName)}){throw "AVD already running: $AvdName"}
    $runtime=Resolve-ValidationPath (Join-Path $OutputDir 'runtime') 'AVD runtime directory' $ValidationDrive
    foreach($dir in @('temp','android-user','emulator-home')){New-Item -ItemType Directory -Path (Join-Path $runtime $dir) -Force|Out-Null}
    $old=@{};foreach($name in @('TEMP','TMP','ANDROID_HOME','ANDROID_SDK_ROOT','ANDROID_USER_HOME','ANDROID_AVD_HOME','ANDROID_EMULATOR_HOME','ANDROID_PREFS_ROOT')){$old[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
    try{
        $env:TEMP=Join-Path $runtime 'temp';$env:TMP=$env:TEMP;$env:ANDROID_HOME=$SdkRoot;$env:ANDROID_SDK_ROOT=$SdkRoot;$env:ANDROID_USER_HOME=Join-Path $runtime 'android-user';$env:ANDROID_PREFS_ROOT=$env:ANDROID_USER_HOME;$env:ANDROID_AVD_HOME=$AvdHome;$env:ANDROID_EMULATOR_HOME=Join-Path $runtime 'emulator-home'
        $devicesResult=Invoke-AdbText $adb @('devices')
        $before=@($devicesResult.text -split "`r?`n"|Where-Object{$_ -match '^emulator-\d+\s+device\b'}|ForEach-Object{($_ -split '\s+')[0]})
        $usedPorts=@(Get-CimInstance Win32_Process|Where-Object{$_.Name -eq 'emulator.exe' -and $_.CommandLine -match '-port\s+(\d+)'}|ForEach-Object{[int]([regex]::Match($_.CommandLine,'-port\s+(\d+)').Groups[1].Value)})
        $port=5620;while(($usedPorts -contains $port) -or (Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue)){$port+=2;if($port -gt 5680){throw 'No free emulator console port in 5620–5680.'}}
        $out=Join-Path $runtime "$AvdName.stdout.log";$err=Join-Path $runtime "$AvdName.stderr.log"
        $proc=Start-Process -FilePath $emulator -ArgumentList @('-avd',$AvdName,'-port',"$port",'-partition-size','2047','-no-snapshot-save','-no-boot-anim','-no-window','-no-metrics','-gpu','swiftshader_indirect') -PassThru -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err
    }finally{foreach($name in $old.Keys){if($null -eq $old[$name]){Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue}else{Set-Item -Path "Env:$name" -Value $old[$name]}}}
    $deadline=[datetime]::UtcNow.AddSeconds($BootTimeoutSeconds);$serial=$null
    while([datetime]::UtcNow -lt $deadline){
        $proc.Refresh()
        if($proc.HasExited){throw "Emulator exited ($($proc.ExitCode)); see $err"}
        $devicesResult=Invoke-AdbText $adb @('devices')
        $new=@($devicesResult.text -split "`r?`n"|Where-Object{$_ -match '^emulator-\d+\s+device\b'}|ForEach-Object{($_ -split '\s+')[0]}|Where-Object{$before -notcontains $_})
        if($new.Count -gt 1){throw 'More than one new emulator appeared.'}
        if($new.Count -eq 1){
            $serial=$new[0]
            $nameResult=Invoke-AdbText $adb @('-s',$serial,'emu','avd','name')
            $actualName=$nameResult.text.Trim()
            if($nameResult.exitCode -eq 0 -and $actualName -match "(?m)^$([regex]::Escape($AvdName))$"){
                $bootResult=Invoke-AdbText $adb @('-s',$serial,'shell','getprop','sys.boot_completed')
                if($bootResult.exitCode -eq 0 -and $bootResult.text.Trim() -eq '1'){break}
            }
        }
        Start-Sleep -Milliseconds 500
    }
    $bootReady=$false
    if($serial){$bootResult=Invoke-AdbText $adb @('-s',$serial,'shell','getprop','sys.boot_completed');$bootReady=$bootResult.exitCode -eq 0 -and $bootResult.text.Trim() -eq '1'}
    if(-not $bootReady){Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue;throw "AVD boot timed out after $BootTimeoutSeconds seconds."}
    $apiResult=Invoke-AdbText $adb @('-s',$serial,'shell','getprop','ro.build.version.sdk')
    $api=$apiResult.text.Trim()
    if($apiResult.exitCode -ne 0 -or $api -ne '35'){Invoke-AdbText $adb @('-s',$serial,'emu','kill')|Out-Null;throw "AVD device reports API '$api'; API 35 is required."}
    $diskNumber=[int](Get-Partition -DriveLetter $ValidationDrive -ErrorAction Stop).DiskNumber
    [pscustomobject]@{serial=$serial;processId=$proc.Id;avdName=$AvdName;dataPath=$avdPath;avdHome=$AvdHome;systemImagePath=$imagePath;apiLevel=[int]$api;drive=$ValidationDrive;diskNumber=$diskNumber}
}

function Stop-PhoneAvd {
    param([Parameter(Mandatory)][psobject]$Session,[Parameter(Mandatory)][string]$SdkRoot)
    $drive=if($Session.drive){[string]$Session.drive}else{'E'}
    $resolved=Resolve-ValidationPath $Session.dataPath 'AVD session data path' $drive
    $avdHome=Resolve-ValidationPath $Session.avdHome 'AVD session home' $drive
    if(-not $resolved.StartsWith(($avdHome.TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){throw 'AVD session path is outside its validated AVD home.'}
    $avdProcesses=@(Get-CimInstance Win32_Process|Where-Object{$_.Name -eq 'emulator.exe' -and $_.CommandLine -match ('(?i)-avd\s+"?'+[regex]::Escape([string]$Session.avdName)+'(?:"|\s)')})
    $owned=@($avdProcesses|Where-Object{[int]$_.ProcessId -eq [int]$Session.processId})
    if($owned.Count -ne 1){throw 'Refusing to stop an AVD process that no longer matches this session.'}
    $adb=Join-Path $SdkRoot 'platform-tools\adb.exe';& $adb -s $Session.serial emu kill 2>$null|Out-Null
    for($i=0;$i -lt 40;$i++){if(-not(Get-Process -Id $Session.processId -ErrorAction SilentlyContinue)){return};Start-Sleep -Milliseconds 250}
    Stop-Process -Id $Session.processId -Force -ErrorAction SilentlyContinue
}

function Wait-PhoneAdbOnline {
    param([Parameter(Mandatory)][string]$Serial,[Parameter(Mandatory)][string]$SdkRoot,[int]$TimeoutSeconds=60)
    $adb=Join-Path $SdkRoot 'platform-tools\adb.exe'
    $deadline=[datetime]::UtcNow.AddSeconds($TimeoutSeconds)
    while([datetime]::UtcNow -lt $deadline){
        $oldPreference=$ErrorActionPreference
        try{
            $ErrorActionPreference='Continue'
            $state=(& $adb -s $Serial get-state 2>$null|Out-String).Trim()
            $exitCode=$LASTEXITCODE
        }finally{$ErrorActionPreference=$oldPreference}
        if($exitCode -eq 0 -and $state -eq 'device'){return}
        Start-Sleep -Milliseconds 500
    }
    throw "ADB device $Serial did not return online within $TimeoutSeconds seconds."
}

function Get-PhoneApkFacts {
    param([Parameter(Mandatory)][string]$ApkPath,[Parameter(Mandatory)][string]$SdkRoot)
    $apkHash=(Get-FileHash -Algorithm SHA256 -LiteralPath $ApkPath).Hash.ToLowerInvariant()
    $buildTools=Join-Path $SdkRoot 'build-tools';$aapt=Get-ChildItem $buildTools -Filter aapt2.exe -Recurse|Sort-Object FullName -Descending|Select-Object -First 1 -ExpandProperty FullName
    if(-not $aapt){throw 'aapt2 is missing from the selected Android SDK.'}
    $badging=(& $aapt dump badging $ApkPath 2>&1|Out-String);if($LASTEXITCODE -ne 0){throw 'aapt2 failed to inspect the APK.'}
    $pkg=[regex]::Match($badging,"package: name='([^']+)' versionCode='(\d+)' versionName='([^']*)'");$min=[regex]::Match($badging,"(?m)^minSdkVersion:'(\d+)'");$target=[regex]::Match($badging,"(?m)^targetSdkVersion:'(\d+)'")
    if(-not $pkg.Success -or -not $min.Success -or -not $target.Success){throw 'APK manifest metadata is incomplete.'}
    $manifest=(& $aapt dump xmltree $ApkPath --file AndroidManifest.xml 2>&1|Out-String);if($LASTEXITCODE -ne 0){throw 'aapt2 failed to inspect the APK manifest.'}
    $debuggable=($badging -match '(?m)^application-debuggable$') -or ($manifest -match 'android:debuggable\([^)]*\)=(?:true|\(type 0x12\)(?:0x1|0xffffffff))')
    $certHash=$null;$signatureV2=$false
    $signer=Get-ChildItem $buildTools -Filter apksigner.bat -Recurse|Sort-Object FullName -Descending|Select-Object -First 1 -ExpandProperty FullName
    if($signer){$sig=(& $signer verify --verbose --print-certs $ApkPath 2>&1|Out-String);if($LASTEXITCODE -eq 0){$signatureV2=$sig -match 'Verified using v2 scheme \(APK Signature Scheme v2\):\s*true';$cert=[regex]::Match($sig,'certificate SHA-256 digest:\s*([0-9a-fA-F:]+)');if($cert.Success){$certHash=$cert.Groups[1].Value.Replace(':','').ToLowerInvariant()}}}
    [pscustomobject]@{packageName=$pkg.Groups[1].Value;sha256=$apkHash;certificateSha256=$certHash;versionName=$pkg.Groups[3].Value;versionCode=[int]$pkg.Groups[2].Value;minSdk=[int]$min.Groups[1].Value;targetSdk=[int]$target.Groups[1].Value;debuggable=[bool]$debuggable;signatureV2=[bool]$signatureV2}
}

function Test-PhoneApk {
    param([string]$ApkPath,[string]$ChecksumsPath,[string]$SdkRoot,[string]$Version,[int]$Build,[string]$CertificateSha256)
    $facts=Get-PhoneApkFacts -ApkPath $ApkPath -SdkRoot $SdkRoot
    $match=@(Get-Content -LiteralPath $ChecksumsPath|Where-Object{$_ -match ('^([0-9a-fA-F]{64})\s+\*?'+[regex]::Escape((Split-Path -Leaf $ApkPath))+'$')})
    if($match.Count -ne 1 -or $match[0].Substring(0,64).ToLowerInvariant() -ne $facts.sha256){throw 'APK SHA-256 does not match its published checksum manifest.'}
    if($facts.packageName -ne 'com.yuanfang.aitext.personal_ai_inbox' -or $facts.versionName -ne $Version -or $facts.versionCode -ne $Build){throw 'APK package/version metadata mismatch.'}
    if($facts.minSdk -ne 24 -or $facts.targetSdk -ne 36){throw 'APK minSdk/targetSdk mismatch.'}
    if($facts.debuggable -or -not $facts.signatureV2){throw 'Published APK must be non-debuggable and have a valid v2 signature.'}
    if($facts.certificateSha256 -ne $CertificateSha256.ToLowerInvariant()){throw 'APK signing certificate does not match the long-lived release key.'}
    $facts
}

function Assert-InstalledVersion {
    param([Parameter(Mandatory)][string]$Serial,[Parameter(Mandatory)][string]$PackageName,[Parameter(Mandatory)][string]$ExpectedVersion,[Parameter(Mandatory)][int]$ExpectedBuild,[Parameter(Mandatory)][string]$SdkRoot)
    Wait-PhoneAdbOnline -Serial $Serial -SdkRoot $SdkRoot
    $adb=Join-Path $SdkRoot 'platform-tools\adb.exe';$dump=(& $adb -s $Serial shell dumpsys package $PackageName 2>&1|Out-String)
    if($LASTEXITCODE -ne 0 -or $dump -notmatch "(?m)^\s*versionCode=$ExpectedBuild\b" -or $dump -notmatch "(?m)^\s*versionName=$([regex]::Escape($ExpectedVersion))\s*$"){throw "Installed package version does not match $ExpectedVersion+$ExpectedBuild."}
}
