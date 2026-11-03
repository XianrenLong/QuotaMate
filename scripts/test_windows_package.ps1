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
    if (-not (Test-Path "$env:APPDATA/QuotaMate/usage.sqlite3")) { throw 'Database was not created' }
    Write-Host 'Extracted Windows package starts with an isolated profile and creates its native window.'
} finally {
    if ($appProcess -and -not $appProcess.HasExited) { Stop-Process -Id $appProcess.Id -Force }
    $env:APPDATA = $previousAppData
    Remove-Item -LiteralPath $temporary -Recurse -Force
}
