# @name         Verify Folder Checksum
# @command      powershell.exe -ExecutionPolicy Bypass -File "%EXTENSION_PATH%" ^
#                   -sessionUrl "!E" -localPath "!^!" -remotePath "!/!" -pause ^
#                   -sessionLogPath "%SessionLogPath%"
# @description  Compares checksums of the selected local and remote folder
# @flag         RemoteFiles
# @version      1
# @homepage     
# @require      WinSCP 5.16
# @option       SessionLogPath -config sessionlogfile
# @optionspage  
 
param (
    # Use Generate Session URL function to obtain a value for -sessionUrl parameter.
    $sessionUrl = "sftp://user:mypassword;fingerprint=ssh-rsa-xxxxxxxxxxx...@example.com/",
    [Parameter(Mandatory = $True)]
    $localPath,
    [Parameter(Mandatory = $True)]
    $remotePath,
    $sessionLogPath = $Null,
    [Switch]
    $pause
)

$filecount = 0
$matchcount = 0
$mismatchcount = 0

Function Mismatch {
    param ($text, $localPath, $remotePath)
    $global:mismatchcount++
    UpdateProgressBar
    Write-Host -ForegroundColor DarkRed $text
    if ($localPath) { Write-Host -ForegroundColor Yellow $localPath }
    if ($remotePath) { Write-Host -ForegroundColor Green $remotePath }
    Write-Host
}

Function UpdateProgressBar {
    $pct = (($global:matchcount + $global:mismatchcount) / $global:filecount) * 100
    if ($pct -gt 100) { $pct = 100 }
    Write-Progress -Activity "Folder Verification (This is a very rough guess, hence it can take a bit at 100% based on how different the folders are)" -Status "$pct% Complete: $global:matchcount matches, $global:mismatchcount mismatches" -PercentComplete $pct
}

Function CheckFolder {
    param ($localPath, $remotePath)
    $a = Get-ChildItem -Path $localPath -Force | Sort-Object
    $c = $global:session.EnumerateRemoteFiles($remotePath, $null, [WinSCP.EnumerationOptions]::MatchDirectories) | Sort-Object

    $li = 0
    $ri = 0

    while ($true) {
        try {
            # Write-Host $a[$li].FullName $c[$ri].FullName

            if ($a[$li].Name -eq $c[$ri].Name) {
                if ($a[$li].GetType().Name -eq "DirectoryInfo" -and $c[$ri].FileType -eq "D") {
                    CheckFolder $a[$li].FullName $c[$ri].FullName
                } elseif ($a[$li].GetType().Name -eq "FileInfo" -and $c[$ri].FileType -eq "-") {
                    # $sw = [Diagnostics.Stopwatch]::StartNew()
                    $sha1 = [System.Security.Cryptography.SHA1]::Create()
                    $localStream = [System.IO.File]::OpenRead($a[$li].FullName)
                    $localChecksum = [System.BitConverter]::ToString($sha1.ComputeHash($localStream))
                    # $sw.Stop()
                    # Write-Host -ForegroundColor DarkGray $sw.Elapsed $a[$li].FullName

                    # $sw1 = [Diagnostics.Stopwatch]::StartNew()
                    $remoteChecksumBytes = $session.CalculateFileChecksum("sha-1", $c[$ri].FullName)
                    $remoteChecksum = [System.BitConverter]::ToString($remoteChecksumBytes)
                    

                    if ($remoteChecksum -eq $localChecksum) {
                        $global:matchcount++
                        UpdateProgressBar
                    } else {
                        Mismatch "Checksum doesn't match" $a[$li].FullName $c[$ri].FullName
                    }

                } else {
                    Mismatch "One of these is a file and one a folder" $a[$li].FullName $c[$ri].FullName
                }
                $li++
                $ri++
            } elseif ($a[$li].Name -gt $c[$ri].Name) {
                Mismatch "File doesn't exist locally" $null $c[$ri].FullName 
                $ri++
            } else {
                Mismatch "File doesn't exist on remote" $a[$li].FullName 
                $li++
            }

            if ($li -eq $a.Length) {
                for (; $ri -lt $c.Length; $ri++) {
                    Mismatch "File doesn't exist on remote" $null $c[$ri].FullName
                }
                break
            }

            if ($ri -eq $c.Length) {
                for (; $li -lt $a.Length; $li++) {
                    Mismatch "File doesn't exist on remote" $a[$li].FullName
                }
                break
            }
        } catch {
            Write-Host -ForegroundColor DarkRed "Error while calculating $($_.Exception.Message)" 
        }
    }
}
 
try {
    # Load WinSCP .NET assembly
    $assemblyPath = if ($env:WINSCP_PATH) { $env:WINSCP_PATH } else { $PSScriptRoot }
    Add-Type -Path (Join-Path $assemblyPath "WinSCPnet.dll")
 
    # Setup session options
    
    $sessionOptions = New-Object WinSCP.SessionOptions -Property @{
        'TimeoutInMilliseconds' = 3600000 # 1hr
    }
    $sessionOptions.ParseUrl($sessionUrl)
 
    $session = New-Object WinSCP.Session
 
    try {
        $session.SessionLogPath = $sessionLogPath

        # Connect
        $session.Open($sessionOptions)

        # place for the progress bar
        Write-Host
        Write-Host
        Write-Host
        Write-Host
        Write-Host
        Write-Host
        Write-Host

        # rouighly guess progress by taking amount of files in local folder 
        $filecount = (Get-ChildItem -Path $localPath -Recurse -Force -File).Length
        # avoid div by zero if folder is empty
        if ($filecount -eq 0) { $filecount = 1 }
        Write-Progress -Activity "Folder Verification (This is a very rough guess, hence it can take a bit at 100% based on how different the folders are)" -Status "0% Complete: $matchcount successes, $mismatchcount mismatches" -PercentComplete 0

        CheckFolder $localPath $remotePath

        Write-Host matchcount $matchcount
    } catch {
        Write-Host "Error: $($_.Exception.Message)"
        [System.Console]::ReadKey() | Out-Null
    }
}
catch {
    Write-Host "Error: $($_.Exception.Message)"
    [System.Console]::ReadKey() | Out-Null
}
 
if ($pause) {
    Write-Host "Press any key to exit..."
    [System.Console]::ReadKey() | Out-Null
}
