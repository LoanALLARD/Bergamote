# End-to-end test of the published app on a real Windows machine, driven like a person would:
# start the app, drag a file out of a window, tap Shift, drop the file on the first slice of the
# wheel, and find the converted file next to the original.
#
#   dotnet publish windows/Bergamote.Windows -c Release -r win-x64 --self-contained -o windows/publish
#   dotnet build windows/Bergamote.DragSource -c Release
#   pwsh -File windows/scripts/smoke-test.ps1
$ErrorActionPreference = "Stop"
$exe = Join-Path $PSScriptRoot "..\publish\Bergamote.exe"
$source = Join-Path $PSScriptRoot "..\Bergamote.DragSource\bin\Release\net8.0-windows\Bergamote.DragSource.exe"
$data = Join-Path $env:LOCALAPPDATA "Bergamote"
$settings = Join-Path $env:APPDATA "Bergamote\settings.json"
$debug = Join-Path $data "debug.log"
$errors = Join-Path $data "bergamote.log"
$work = Join-Path ([System.IO.Path]::GetTempPath()) "bergamote-smoke-$PID"
Remove-Item -Recurse -Force $data -ErrorAction SilentlyContinue
Remove-Item -Force $settings -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $work | Out-Null

# The file to convert: a small PNG.
Add-Type -AssemblyName System.Drawing
$bitmap = New-Object System.Drawing.Bitmap 400, 300
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.Clear([System.Drawing.Color]::FromArgb(195, 207, 58))
$graphics.Dispose()
$photo = Join-Path $work "photo.png"
$bitmap.Save($photo, [System.Drawing.Imaging.ImageFormat]::Png)
$bitmap.Dispose()

Add-Type -Namespace Smoke -Name Input -MemberDefinition @"
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, System.UIntPtr extra);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern void keybd_event(byte key, byte scan, uint flags, System.UIntPtr extra);
"@
function Move-Pointer($x, $y) {
    [Smoke.Input]::SetCursorPos($x, $y) | Out-Null
    [Smoke.Input]::mouse_event(0x0001, 0, 0, 0, [UIntPtr]::Zero)   # a move event, so every window notices
    Start-Sleep -Milliseconds 40
}

$env:BERGAMOTE_DEBUG = "1"
$env:BERGAMOTE_DRAG_LOG = Join-Path $work "drag.log"
$app = Start-Process -FilePath $exe -PassThru
$drag = $null
$failed = $false
$report = @()
function Check($ok, $label) {
    $line = if ($ok) { "ok     $label" } else { "FAILED $label" }
    Write-Host $line
    $script:report += $line
    if (-not $ok) { $script:failed = $true }
}
function Logged($pattern) { (Test-Path $debug) -and ((Get-Content $debug -Raw) -match $pattern) }
try {
    # The single-file executable unpacks itself on first start: allow it some time.
    $deadline = (Get-Date).AddSeconds(60)
    while (-not (Test-Path $debug) -and -not $app.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
    Check (Test-Path $debug) "the app starts and loads the shared core"
    Check (Test-Path $settings) "settings are written on first launch"

    $drag = Start-Process -FilePath $source -ArgumentList "`"$photo`"" -PassThru
    Start-Sleep -Seconds 4

    # Press inside the drag source, then drag step by step towards the middle of the screen.
    Move-Pointer 200 180
    Start-Sleep -Milliseconds 300
    [Smoke.Input]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 200
    for ($step = 1; $step -le 20; $step++) { Move-Pointer (200 + $step * 22) (180 + $step * 11) }
    Start-Sleep -Milliseconds 500

    # Tap Shift: the conversion wheel opens under the pointer (640, 400).
    [Smoke.Input]::keybd_event(0x10, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 200
    [Smoke.Input]::keybd_event(0x10, 0, 2, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 400
    Move-Pointer 642 401
    Move-Pointer 640 400
    Start-Sleep -Milliseconds 1200
    Check (Logged "gesture: Conversion") "the gesture (drag, then Shift) is detected"
    Check (Logged "slices: convert_images:jpeg") "the wheel receives the dragged file and offers its slices"

    # To the first slice (top), then drop.
    for ($step = 1; $step -le 11; $step++) { Move-Pointer 640 (400 - $step * 10) }
    Start-Sleep -Milliseconds 600
    [Smoke.Input]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
    $deadline = (Get-Date).AddSeconds(15)
    while (-not (Logged "result: ") -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
    Check (Logged "result: 1 ") "dropping on the JPEG slice converts the file"
    $converted = Join-Path $work "photo.jpeg"
    Check ((Test-Path $converted) -and ((Get-Item $converted).Length -gt 0)) "photo.jpeg is created next to the original"
    Check (Test-Path $photo) "the original is still there"

    # Launching the app again while it runs opens its settings window.
    Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
    $automation = [System.Windows.Automation.AutomationElement]
    function Find-Window($title) {
        $condition = New-Object System.Windows.Automation.PropertyCondition($automation::NameProperty, $title)
        $deadline = (Get-Date).AddSeconds(15)
        do {
            $window = $automation::RootElement.FindFirst([System.Windows.Automation.TreeScope]::Children, $condition)
            if ($window) { return $window }
            Start-Sleep -Milliseconds 300
        } while ((Get-Date) -lt $deadline)
        return $null
    }
    function Find-Inside($parent, $name) {
        $condition = New-Object System.Windows.Automation.PropertyCondition($automation::NameProperty, $name)
        return $parent.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
    }
    Start-Process -FilePath $exe -Wait
    $window = Find-Window "Bergamote Settings"
    Check ($null -ne $window) "launching the app again opens its settings"
    if ($window) {
        # Start at login: ticking the box writes the Run entry of the user, unticking removes it.
        $run = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
        $box = Find-Inside $window "Start Bergamote at login"
        $toggle = $box.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
        $toggle.Toggle()
        Start-Sleep -Milliseconds 500
        $entry = (Get-ItemProperty -Path $run -ErrorAction SilentlyContinue).Bergamote
        Check ($entry -and $entry.Contains("Bergamote.exe")) "ticking 'Start at login' registers the app to run at sign-in"

        # What Windows does at sign-in: run that registered command. The app must come up from it.
        $app.Kill()
        $app.WaitForExit()
        Remove-Item -Force $debug -ErrorAction SilentlyContinue
        if ($entry) { Start-Process -FilePath $entry.Trim('"') }
        $deadline = (Get-Date).AddSeconds(60)
        while (-not (Test-Path $debug) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
        $restarted = Get-Process -Name Bergamote -ErrorAction SilentlyContinue | Select-Object -First 1
        Check (($null -ne $restarted) -and (Test-Path $debug)) "the registered command starts the app, as a sign-in would"
        if ($restarted) { $app = $restarted }

        # Back in the settings of that new instance, untick the box.
        Start-Process -FilePath $exe -Wait
        $window = Find-Window "Bergamote Settings"
        $box = Find-Inside $window "Start Bergamote at login"
        $toggle = $box.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
        Check ($toggle.Current.ToggleState -eq [System.Windows.Automation.ToggleState]::On) "the setting is shown as on after the restart"
        $toggle.Toggle()
        Start-Sleep -Milliseconds 500
        $entry = (Get-ItemProperty -Path $run -ErrorAction SilentlyContinue).Bergamote
        Check (-not $entry) "unticking it removes the registration"

        # Language: choosing French rebuilds the window in French, at once.
        # The language list is the last one of the window; its items exist once it has been opened.
        $isList = New-Object System.Windows.Automation.PropertyCondition($automation::ControlTypeProperty, [System.Windows.Automation.ControlType]::ComboBox)
        $lists = $window.FindAll([System.Windows.Automation.TreeScope]::Descendants, $isList)
        $item = $null
        if ($lists.Count -gt 0) {
            $list = $lists[$lists.Count - 1]
            $list.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand()
            Start-Sleep -Milliseconds 600
            $item = Find-Inside $list "Français"
        }
        if ($item) { $item.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select() }
        $french = Find-Window "Réglages de Bergamote"
        Check ($null -ne $french) "choosing French switches the settings window to French at once"
        Check ((Test-Path $settings) -and ((Get-Content $settings -Raw) -match '"Language":\s*"fr"')) "the language choice is saved"
        if ($french) { $french.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close() }
    }

    Check (-not $app.HasExited) "the app is still running"
    $logged = (Test-Path $errors) -and ((Get-Item $errors).Length -gt 0)
    Check (-not $logged) "no error was logged"

    Write-Host "--- app log ---"
    if (Test-Path $debug) { Get-Content $debug | ForEach-Object { Write-Host "       $_" } }
    if (Test-Path $env:BERGAMOTE_DRAG_LOG) { Get-Content $env:BERGAMOTE_DRAG_LOG | ForEach-Object { Write-Host "       $_" } }
    if ($logged) { Get-Content $errors | Select-Object -First 30 | ForEach-Object { Write-Host "       $_" } }
} finally {
    [Smoke.Input]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
    if ($drag -and -not $drag.HasExited) { $drag.Kill() }
    if (-not $app.HasExited) { $app.Kill() }
}
# The result, visible on the run summary without opening the log.
$level = if ($failed) { "error" } else { "notice" }
Write-Host ("::{0} title=Windows end-to-end test::{1}" -f $level, ($report -join "%0A"))
if ($failed) { exit 1 }
