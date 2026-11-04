$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectDirectory = Split-Path -Parent $PSScriptRoot
$temporary = Join-Path $env:RUNNER_TEMP ('QuotaMate smoke ' + [guid]::NewGuid().ToString())
New-Item -ItemType Directory -Force $temporary | Out-Null
$previousAppData = $env:APPDATA
$appProcess = $null
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class QuotaMateWindow {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string cls, string name);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr GetProp(IntPtr hwnd, string name);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hwnd, uint message, IntPtr wparam, IntPtr lparam);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
}
'@
function Wait-QuotaMateWindow {
    for ($attempt = 0; $attempt -lt 50; $attempt++) {
        Start-Sleep -Milliseconds 200
        $hwnd = [QuotaMateWindow]::FindWindow('FLUTTER_RUNNER_WIN32_WINDOW','QuotaMate')
        if ($hwnd -ne [IntPtr]::Zero -and [QuotaMateWindow]::GetProp($hwnd,'QuotaMate.CloseToTray') -ne [IntPtr]::Zero) { return $hwnd }
    }
    throw 'Window preferences were not initialized'
}
try {
    $zip = Get-ChildItem "$projectDirectory/dist/windows/QuotaMate-*-windows-x64.zip" |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    Expand-Archive -LiteralPath $zip.FullName -DestinationPath "$temporary/portable"
    $env:APPDATA = "$temporary/profile"
    New-Item -ItemType Directory -Force "$env:APPDATA/QuotaMate" | Out-Null
    # Disable source access before startup; this smoke test never touches client accounts.
    python -c "import sqlite3,json,os; p=os.path.join(os.environ['APPDATA'],'QuotaMate','usage.sqlite3'); c=sqlite3.connect(p); c.execute('CREATE TABLE settings(key TEXT PRIMARY KEY,value TEXT NOT NULL)'); c.execute('INSERT INTO settings VALUES(?,?)',('preferences',json.dumps({'scanEnabled':False,'quotaEnabled':False,'autoRefresh':False,'closeToTray':True}))); c.commit(); c.close()"
    $appProcess = Start-Process "$temporary/portable/quota_mate.exe" -PassThru
    $ready = $false
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        Start-Sleep -Milliseconds 500
        $appProcess.Refresh()
        if ($appProcess.HasExited) { throw "Packaged application exited: $($appProcess.ExitCode)" }
        if ($appProcess.MainWindowHandle -ne 0 -and $appProcess.MainWindowTitle -eq 'QuotaMate') { $ready = $true; break }
    }
    if (-not $ready) { throw 'Packaged application did not create its window' }
    python -c "import sqlite3,json,os; c=sqlite3.connect(os.path.join(os.environ['APPDATA'],'QuotaMate','usage.sqlite3')); assert c.execute('PRAGMA user_version').fetchone()[0]==3; p=json.loads(c.execute('SELECT value FROM settings WHERE key=?',('preferences',)).fetchone()[0]); assert len(p['prices'])==25; c.close()"
    if ($LASTEXITCODE -ne 0) { throw 'Application database migration/default pricing check failed' }
    $hwnd = Wait-QuotaMateWindow
    $tray = [QuotaMateWindow]::GetProp($hwnd,'QuotaMate.TrayAvailable') -ne [IntPtr]::Zero
    Write-Host "Tray support in this Windows session: $tray"
    if ($tray) {
        # NIN_SELECT with a bottom-right anchor, as a left click on the tray icon sends.
        [QuotaMateWindow]::PostMessage($hwnd,0x802A,[IntPtr](700 -bor (740 -shl 16)),[IntPtr]0x0400) | Out-Null
        $panel = [IntPtr]::Zero
        for ($attempt = 0; $attempt -lt 20 -and ($panel -eq [IntPtr]::Zero -or -not [QuotaMateWindow]::IsWindowVisible($panel)); $attempt++) {
            Start-Sleep -Milliseconds 200
            $panel = [QuotaMateWindow]::FindWindow('QuotaMateTrayPanel','QuotaMate')
        }
        if ($panel -eq [IntPtr]::Zero -or -not [QuotaMateWindow]::IsWindowVisible($panel)) { throw 'Tray click did not open the panel' }
        Start-Sleep -Milliseconds 500
        $bounds = New-Object QuotaMateWindow+RECT
        [QuotaMateWindow]::GetWindowRect($panel,[ref]$bounds) | Out-Null
        if (($bounds.Right - $bounds.Left) -lt 300 -or ($bounds.Bottom - $bounds.Top) -lt 200) { throw 'Tray panel has an unexpected size' }
        # On GitHub Actions the screenshot joins the uploaded test packages for review.
        $screenshot = $env:QUOTAMATE_PANEL_SCREENSHOT
        if (-not $screenshot -and $env:GITHUB_ACTIONS -eq 'true') { $screenshot = "$projectDirectory/dist/windows/tray-panel-smoke.png" }
        if ($screenshot) {
            Add-Type -AssemblyName System.Drawing
            $image = New-Object System.Drawing.Bitmap ($bounds.Right - $bounds.Left), ($bounds.Bottom - $bounds.Top)
            $canvas = [System.Drawing.Graphics]::FromImage($image)
            $canvas.CopyFromScreen($bounds.Left, $bounds.Top, 0, 0, $image.Size)
            $image.Save($screenshot, [System.Drawing.Imaging.ImageFormat]::Png)
            $canvas.Dispose(); $image.Dispose()
        }
        [QuotaMateWindow]::PostMessage($panel,0x0100,[IntPtr]0x1B,[IntPtr]::Zero) | Out-Null
        Start-Sleep -Milliseconds 300
        if ([QuotaMateWindow]::IsWindowVisible($panel)) { throw 'Escape did not close the tray panel' }
    }
    [QuotaMateWindow]::PostMessage($hwnd,0x0010,[IntPtr]::Zero,[IntPtr]::Zero) | Out-Null
    Start-Sleep -Milliseconds 500
    $appProcess.Refresh()
    if ($tray) {
        if ($appProcess.HasExited -or [QuotaMateWindow]::IsWindowVisible($hwnd)) { throw 'Closing to the tray failed' }
        $second = Start-Process "$temporary/portable/quota_mate.exe" -PassThru
        if (-not $second.WaitForExit(10000) -or $second.ExitCode -ne 0) { throw 'Single-instance activation failed' }
        if (-not [QuotaMateWindow]::IsWindowVisible($hwnd)) { throw 'The original window was not restored' }
        [QuotaMateWindow]::PostMessage($hwnd,0x802B,[IntPtr]::Zero,[IntPtr]::Zero) | Out-Null
        if (-not $appProcess.WaitForExit(10000)) { throw 'Explicit tray quit did not exit' }
    } elseif (-not $appProcess.WaitForExit(10000)) { throw 'No-tray fallback did not exit' }
    $appProcess = Start-Process "$temporary/portable/quota_mate.exe" -ArgumentList '--background' -PassThru
    $hwnd = Wait-QuotaMateWindow
    $tray = [QuotaMateWindow]::GetProp($hwnd,'QuotaMate.TrayAvailable') -ne [IntPtr]::Zero
    if ($tray -and [QuotaMateWindow]::IsWindowVisible($hwnd)) { throw 'Background startup unexpectedly opened a window' }
    if (-not $tray -and -not [QuotaMateWindow]::IsWindowVisible($hwnd)) { throw 'Missing-tray fallback left an inaccessible background app' }
    [QuotaMateWindow]::PostMessage($hwnd,0x802B,[IntPtr]::Zero,[IntPtr]::Zero) | Out-Null
    if (-not $appProcess.WaitForExit(10000)) { throw 'Background instance did not quit' }
    $appProcess = $null
    $installer = Get-ChildItem "$projectDirectory/dist/windows/QuotaMate-*-windows-x64-setup.exe" |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $installation = Join-Path $temporary 'installed application'
    $setup = Start-Process -FilePath $installer.FullName -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',"/DIR=`"$installation`"") -Wait -PassThru
    if ($setup.ExitCode -ne 0 -or -not (Test-Path "$installation/quota_mate.exe")) { throw 'Installer smoke test failed' }
    $uninstall = Start-Process -FilePath "$installation/unins000.exe" -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART') -Wait -PassThru
    if ($uninstall.ExitCode -ne 0) { throw 'Uninstaller smoke test failed' }
    if (-not (Test-Path "$env:APPDATA/QuotaMate/usage.sqlite3")) { throw 'Uninstall unexpectedly deleted user data' }
    Write-Host 'Portable package starts, initializes SQLite/default prices, and installer/uninstaller preserve user data.'
} finally {
    if ($appProcess -and -not $appProcess.HasExited) { Stop-Process -Id $appProcess.Id -Force }
    $env:APPDATA = $previousAppData
    Remove-Item -LiteralPath $temporary -Recurse -Force
}
