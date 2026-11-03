$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectDirectory = Split-Path -Parent $PSScriptRoot
$temporary = Join-Path $env:RUNNER_TEMP ('QuotaMate smoke ' + [guid]::NewGuid().ToString())
New-Item -ItemType Directory -Force $temporary | Out-Null
$previousAppData = $env:APPDATA
$appProcess = $null
try {
    $zip = Get-ChildItem "$projectDirectory/dist/windows/QuotaMate-*-windows-x64.zip" |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    Expand-Archive -LiteralPath $zip.FullName -DestinationPath "$temporary/portable"
    $env:APPDATA = "$temporary/profile"
    New-Item -ItemType Directory -Force "$env:APPDATA/QuotaMate" | Out-Null
    # Disable source access before startup; this smoke test never touches client accounts.
    python -c "import sqlite3,json,os; p=os.path.join(os.environ['APPDATA'],'QuotaMate','usage.sqlite3'); c=sqlite3.connect(p); c.execute('CREATE TABLE settings(key TEXT PRIMARY KEY,value TEXT NOT NULL)'); c.execute('INSERT INTO settings VALUES(?,?)',('preferences',json.dumps({'scanEnabled':False,'quotaEnabled':False,'autoRefresh':False}))); c.commit(); c.close()"
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
    Stop-Process -Id $appProcess.Id -Force
    $appProcess.WaitForExit()
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
