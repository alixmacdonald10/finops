# Runs once as SYSTEM via VM Run Command.
# Do not use dollar-brace or percent-brace sequences outside template placeholders.

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
# Prefer TLS 1.3; TLS 1.2 kept as fallback for endpoints without 1.3.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls13 -bor [Net.SecurityProtocolType]::Tls12

$root = 'C:\ProgramData\devvm'
New-Item -ItemType Directory -Path $root -Force | Out-Null

# Visual C++ 2015-2022 x64 runtime (vcruntime140.dll): Neovim needs it; Server 2025 image lacks it.
if (-not (Test-Path "$env:WINDIR\System32\vcruntime140.dll")) {
    $vcExe = Join-Path $root 'vc_redist.x64.exe'
    Invoke-WebRequest -Uri 'https://aka.ms/vs/17/release/vc_redist.x64.exe' -OutFile $vcExe -UseBasicParsing

    # No published digest for the aka.ms link: require a valid Microsoft Authenticode signature.
    $vcSig = Get-AuthenticodeSignature -FilePath $vcExe
    if ($vcSig.Status -ne 'Valid' -or $vcSig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
        Remove-Item $vcExe -Force
        throw "VC++ redist signature check failed: $($vcSig.Status) $($vcSig.SignerCertificate.Subject)"
    }

    $p = Start-Process -FilePath $vcExe -ArgumentList '/install /quiet /norestart' -Wait -PassThru
    # 1638 = newer version already installed, 3010 = reboot required
    if ($p.ExitCode -notin 0, 1638, 3010) { throw "VC++ redist install failed: $($p.ExitCode)" }
    Remove-Item $vcExe -Force
}

# Neovim
$nvimVersion = '${neovim_version}'
$msi = Join-Path $root "nvim-$nvimVersion-win64.msi"
if (-not (Test-Path 'C:\Program Files\Neovim\bin\nvim.exe')) {
    $url = "https://github.com/neovim/neovim/releases/download/$nvimVersion/nvim-win64.msi"
    Invoke-WebRequest -Uri $url -OutFile $msi -UseBasicParsing

    # Integrity check before running as SYSTEM: accept a valid Authenticode signature; if the MSI
    # is unsigned, require its SHA-256 to match the digest GitHub publishes for the release asset.
    $sig = Get-AuthenticodeSignature -FilePath $msi
    if ($sig.Status -eq 'Valid') {
        Write-Output "Neovim MSI signed by $($sig.SignerCertificate.Subject)"
    } elseif ($sig.Status -eq 'NotSigned') {
        $release  = Invoke-RestMethod -Uri "https://api.github.com/repos/neovim/neovim/releases/tags/$nvimVersion" -UseBasicParsing
        $asset    = $release.assets | Where-Object { $_.name -eq 'nvim-win64.msi' }
        $expected = if ($asset -and $asset.digest) { ($asset.digest -replace '^sha256:', '').ToLower() } else { '' }
        $actual   = (Get-FileHash -Path $msi -Algorithm SHA256).Hash.ToLower()
        if (-not $expected -or $expected -ne $actual) {
            Remove-Item $msi -Force
            throw "Neovim MSI is unsigned and SHA-256 does not match GitHub digest (expected '$expected', got '$actual')"
        }
        Write-Output "Neovim MSI unsigned; SHA-256 matches GitHub release digest"
    } else {
        Remove-Item $msi -Force
        throw "Neovim MSI signature check failed: $($sig.Status)"
    }

    $p = Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn /norestart" -Wait -PassThru
    if ($p.ExitCode -notin 0, 3010) { throw "Neovim install failed: $($p.ExitCode)" }
    Remove-Item $msi -Force
}

# Windows Update: install Sunday 01:00, active hours 08-17
$wu = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
$au = Join-Path $wu 'AU'
New-Item -Path $au -Force | Out-Null
Set-ItemProperty -Path $au -Name NoAutoUpdate -Type DWord -Value 0
Set-ItemProperty -Path $au -Name AUOptions -Type DWord -Value 4            # auto download + scheduled install
Set-ItemProperty -Path $au -Name ScheduledInstallDay -Type DWord -Value 1  # Sunday
Set-ItemProperty -Path $au -Name ScheduledInstallTime -Type DWord -Value 1 # 01:00
Set-ItemProperty -Path $au -Name AlwaysAutoRebootAtScheduledTime -Type DWord -Value 1
Set-ItemProperty -Path $wu -Name SetActiveHours -Type DWord -Value 1
Set-ItemProperty -Path $wu -Name ActiveHoursStart -Type DWord -Value 8
Set-ItemProperty -Path $wu -Name ActiveHoursEnd -Type DWord -Value 17

# SSH keys: generated per user at first logon
$keygen = Join-Path $root 'ssh-keygen.ps1'
@'
$ErrorActionPreference = 'Stop'
$ssh = Join-Path $env:USERPROFILE '.ssh'
New-Item -ItemType Directory -Path $ssh -Force | Out-Null
$comment = "$env:USERNAME@$env:COMPUTERNAME"

# ed25519 for GitHub, RSA 4096 for Azure DevOps (RSA is the reliably supported type there).
$keys = @(
    @{ File = 'id_ed25519'; Args = '-t ed25519' },
    @{ File = 'id_rsa';     Args = '-t rsa -b 4096' }
)
foreach ($k in $keys) {
    $path = Join-Path $ssh $k.File
    if (-not (Test-Path $path)) {
        Start-Process -FilePath "$env:WINDIR\System32\OpenSSH\ssh-keygen.exe" `
            -ArgumentList "$($k.Args) -f `"$path`" -N `"`" -C `"$comment`" -q" `
            -Wait -NoNewWindow
    }
}

$config = Join-Path $ssh 'config'
if (-not (Test-Path $config)) {
    @"
Host github.com
    User git
    IdentityFile ~/.ssh/id_ed25519

Host ssh.dev.azure.com
    User git
    IdentityFile ~/.ssh/id_rsa
"@ | Set-Content -Path $config -Encoding ascii
}
'@ | Set-Content -Path $keygen -Encoding UTF8

$taskName = 'devvm-ssh-keygen'
$action    = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$keygen`""
$trigger   = New-ScheduledTaskTrigger -AtLogOn
$principal = New-ScheduledTaskPrincipal -GroupId 'BUILTIN\Users' -RunLevel Limited
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
    -Principal $principal -Force | Out-Null

Write-Output 'setup complete'
