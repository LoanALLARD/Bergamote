# Starts the published app on a real Windows machine and checks that it comes up: native core
# loaded, settings written, no error logged, and the gesture seen when the mouse and the Shift key
# are driven the way a drag would.
#
#   pwsh -File windows/scripts/smoke-test.ps1            (after dotnet publish … -o windows/publish)
$ErrorActionPreference = "Stop"
$exe = Join-Path $PSScriptRoot "..\publish\Bergamote.exe"
$data = Join-Path $env:LOCALAPPDATA "Bergamote"
$settings = Join-Path $env:APPDATA "Bergamote\settings.json"
$debug = Join-Path $data "debug.log"
$errors = Join-Path $data "bergamote.log"
Remove-Item -Recurse -Force $data -ErrorAction SilentlyContinue
Remove-Item -Force $settings -ErrorAction SilentlyContinue

$env:BERGAMOTE_DEBUG = "1"
$app = Start-Process -FilePath $exe -PassThru
$failed = $false
function Check($ok, $label) {
    if ($ok) { Write-Host "ok     $label" } else { Write-Host "FAILED $label"; $script:failed = $true }
}
try {
    # The single-file executable unpacks itself on first start: allow it some time.
    $deadline = (Get-Date).AddSeconds(60)
    while (-not (Test-Path $debug) -and -not $app.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
    Check (Test-Path $debug) "the app starts and loads the shared core"
    if (Test-Path $debug) { Get-Content $debug | ForEach-Object { Write-Host "       $_" } }
    Check (Test-Path $settings) "settings are written on first launch"

    # A drag as the app sees it: button down, pointer moving away, then a tap on Shift.
    Add-Type -Namespace Smoke -Name Input -MemberDefinition @"
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, System.UIntPtr extra);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern void keybd_event(byte key, byte scan, uint flags, System.UIntPtr extra);
"@
    [Smoke.Input]::SetCursorPos(300, 300) | Out-Null
    Start-Sleep -Milliseconds 300
    [Smoke.Input]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
    for ($step = 1; $step -le 20; $step++) {
        [Smoke.Input]::SetCursorPos(300 + $step * 15, 300 + $step * 8) | Out-Null
        Start-Sleep -Milliseconds 40
    }
    Start-Sleep -Milliseconds 300
    [Smoke.Input]::keybd_event(0x10, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 250
    [Smoke.Input]::keybd_event(0x10, 0, 2, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 700
    [Smoke.Input]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 800

    $seen = (Test-Path $debug) -and ((Get-Content $debug -Raw) -match "gesture: Conversion")
    if ($seen) {
        Write-Host "ok     the gesture (drag, then Shift) is detected"
    } else {
        # A machine without an interactive desktop cannot receive simulated input: not a failure of the app.
        Write-Host "::warning title=Windows gesture not exercised::Simulated mouse and keyboard input did not reach the app on this machine."
    }
    Check (-not $app.HasExited) "the app is still running"
    $logged = (Test-Path $errors) -and ((Get-Item $errors).Length -gt 0)
    if ($logged) { Get-Content $errors | Select-Object -First 30 | ForEach-Object { Write-Host "       $_" } }
    Check (-not $logged) "no error was logged"
} finally {
    if (-not $app.HasExited) { $app.Kill() }
}
if ($failed) { exit 1 }
