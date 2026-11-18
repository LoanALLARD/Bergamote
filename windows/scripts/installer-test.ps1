# Installs Bergamote with its setup program, the way a silent deployment would, checks what it
# put on the machine, starts the installed app, then uninstalls it.
#
#   pwsh -File windows/scripts/installer-test.ps1            (after the installer has been built)
$ErrorActionPreference = "Stop"
$setup = Get-ChildItem (Join-Path $PSScriptRoot "..\publish\Bergamote-Setup-*.exe") | Select-Object -First 1
$installed = Join-Path $env:LOCALAPPDATA "Programs\Bergamote\Bergamote.exe"
$shortcut = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Bergamote.lnk"
$uninstaller = Join-Path $env:LOCALAPPDATA "Programs\Bergamote\unins000.exe"
$failed = $false
$report = @()
function Check($ok, $label) {
    $line = if ($ok) { "ok     $label" } else { "FAILED $label" }
    Write-Host $line
    $script:report += $line
    if (-not $ok) { $script:failed = $true }
}

Check ($null -ne $setup) "the setup program was built"
if ($setup) {
    $install = Start-Process -FilePath $setup.FullName -ArgumentList "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART" -Wait -PassThru
    Check ($install.ExitCode -eq 0) "the setup program installs without asking for administrator rights"
    Check (Test-Path $installed) "the app is installed in the user's Programs folder"
    Check (Test-Path $shortcut) "a Start menu shortcut is created"
    Check (Test-Path $uninstaller) "an uninstaller is registered"

    if (Test-Path $installed) {
        $app = Start-Process -FilePath $installed -PassThru
        Start-Sleep -Seconds 8
        Check (-not $app.HasExited) "the installed app starts and keeps running"
        if (-not $app.HasExited) { $app.Kill(); $app.WaitForExit() }
    }
    if (Test-Path $uninstaller) {
        $removal = Start-Process -FilePath $uninstaller -ArgumentList "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART" -Wait -PassThru
        Start-Sleep -Seconds 3
        Check ($removal.ExitCode -eq 0 -and -not (Test-Path $installed)) "uninstalling removes the app"
        Check (-not (Test-Path $shortcut)) "and its Start menu shortcut"
    }
}
$level = if ($failed) { "error" } else { "notice" }
Write-Host ("::{0} title=Windows installer test::{1}" -f $level, ($report -join "%0A"))
if ($failed) { exit 1 }
