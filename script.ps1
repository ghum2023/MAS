if (-not $args) {
    Write-Host
    Write-Host 'Starting installation script...' -ForegroundColor Green
    Write-Host
}

& {
    $psv = (Get-Host).Version.Major

    if ($ExecutionContext.SessionState.LanguageMode.value__ -ne 0) {
        $ExecutionContext.SessionState.LanguageMode
        Write-Host "Error: PowerShell is not running in Full Language Mode." -ForegroundColor Red
        return
    }

    try {
        [void][System.AppDomain]::CurrentDomain.GetAssemblies(); [void][System.Math]::Sqrt(144)
    }
    catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "PowerShell failed to load required .NET components." -ForegroundColor Red
        return
    }

    function Check3rdAV {
        $cmd = if ($psv -ge 3) { 'Get-CimInstance' } else { 'Get-WmiObject' }
        $avList = & $cmd -Namespace root\SecurityCenter2 -Class AntiVirusProduct | Where-Object { $_.displayName -notlike '*windows*' } | Select-Object -ExpandProperty displayName

        if ($avList) {
            Write-Host '3rd party Antivirus might be blocking the script - ' -ForegroundColor White -BackgroundColor Blue -NoNewline
            Write-Host " $($avList -join ', ')" -ForegroundColor DarkRed -BackgroundColor White
        }
    }

    function CheckFile {
        param ([string]$FilePath)
        if (-not (Test-Path $FilePath)) {
            Check3rdAV
            Write-Host "Failed to create temporary file in temp folder, aborting!" -ForegroundColor Red
            throw
        }
    }

    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

    # استبدل الرابط أدناه برابط الـ Raw المباشر لملف MAS_AIO.cmd الخاص بك على GitHub
    $URLs = @(
        'https://raw.githubusercontent.com/ghum2023/MAS/refs/heads/main/MAS/All-In-One-Version-KL/MAS_AIO.cmd'
    )

    Write-Progress -Activity "Downloading..." -Status "Please wait"
    $errors = @()
    foreach ($URL in $URLs | Sort-Object { Get-Random }) {
        try {
            if ($psv -ge 3) {
                $response = Invoke-RestMethod $URL
            }
            else {
                $w = New-Object Net.WebClient
                $response = $w.DownloadString($URL)
            }
            break
        }
        catch {
            $errors += $_
        }
    }
    Write-Progress -Activity "Downloading..." -Status "Done" -Completed

    if (-not $response) {
        Check3rdAV
        foreach ($err in $errors) {
            Write-Host "Error: $($err.Exception.Message)" -ForegroundColor Red
        }
        Write-Host "Failed to retrieve the script from the repository, aborting!" -ForegroundColor Red
        Write-Host "Check if antivirus or firewall is blocking the connection." -ForegroundColor Yellow
        return
    }

    # Verify script integrity & Display Hash
    # ضع قيمة الهاش الخاصة بملفك هنا، أو اتركها كما هي لنسخ الهاش المطبوع عند التشغيل الأول
    $releaseHash = '5FBE0C2753508054BC73455DA94B7F2E0361615215A567B1969F2803FFB79E56'
    $stream = New-Object IO.MemoryStream
    $writer = New-Object IO.StreamWriter $stream
    $writer.Write($response)
    $writer.Flush()
    $stream.Position = 0
    $hash = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($stream)) -replace '-'

    # عرض الهاش المحسوب للملف المُنزل
    Write-Host "Downloaded File Hash: $hash" -ForegroundColor Yellow

    if ($releaseHash -and ($hash -ne $releaseHash)) {
        Write-Warning "Hash mismatch!`nExpected : $releaseHash`nGot      : $hash`nAborting!"
        $response = $null
        return
    }

    # Check for AutoRun registry which may create issues with CMD
    $paths = "HKCU:\SOFTWARE\Microsoft\Command Processor", "HKLM:\SOFTWARE\Microsoft\Command Processor"
    foreach ($path in $paths) { 
        if (Get-ItemProperty -Path $path -Name "Autorun" -ErrorAction SilentlyContinue) { 
            Write-Warning "Autorun registry found, CMD may crash! `nManually copy-paste the below command to fix...`nRemove-ItemProperty -Path '$path' -Name 'Autorun'"
        } 
    }

    $rand = [Guid]::NewGuid().Guid
    $isAdmin = [bool]([Security.Principal.WindowsIdentity]::GetCurrent().Groups -match 'S-1-5-32-544')
    $FilePath = if ($isAdmin) { "$env:SystemRoot\Temp\MAS_$rand.cmd" } else { "$env:USERPROFILE\AppData\Local\Temp\MAS_$rand.cmd" }
    Set-Content -Path $FilePath -Value "@::: $rand `r`n$response"
    CheckFile $FilePath

    $env:ComSpec = "$env:SystemRoot\system32\cmd.exe"
    $chkcmd = & $env:ComSpec /c "echo CMD is working"
    if ($chkcmd -notcontains "CMD is working") {
        Write-Warning "cmd.exe is not working properly."
    }

    if ($psv -lt 3) {
        if (Test-Path "$env:SystemRoot\Sysnative") {
            Write-Warning "Command is running with x86 Powershell, run it with x64 Powershell instead..."
            return
        }
        $p = Start-Process -FilePath $env:ComSpec -ArgumentList "/c """"$FilePath"" -el -qedit $args""" -Verb RunAs -PassThru
        $p.WaitForExit()
    }
    else {
        Start-Process -FilePath $env:ComSpec -ArgumentList "/c """"$FilePath"" -el $args""" -Wait -Verb RunAs
    }	
	
    CheckFile $FilePath
    Remove-Item -Path $FilePath
} @args