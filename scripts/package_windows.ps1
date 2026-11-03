param([switch]$SkipBuild)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectDirectory = Split-Path -Parent $PSScriptRoot
Push-Location $projectDirectory
try {
    python scripts/prepare_windows.py
    if ($LASTEXITCODE -ne 0) { throw 'SQLite preparation failed' }
    if (-not $SkipBuild) {
        flutter build windows --release --target-platform windows-x64
        if ($LASTEXITCODE -ne 0) { throw 'Windows build failed' }
    }
    $release = Join-Path $projectDirectory 'build/windows/x64/runner/Release'
    dart compile exe scripts/claude_statusline.dart -o "$release/quotamate-claude-statusline.exe"
    if ($LASTEXITCODE -ne 0) { throw 'Metadata relay build failed' }
    # Bundle the app-local MSVC runtime; users do not need Visual Studio.
    $vswhere = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
    $visualStudio = & $vswhere -latest -products '*' -property installationPath
    $runtime = Get-ChildItem "$visualStudio/VC/Redist/MSVC/*/x64/Microsoft.VC*.CRT" -Directory |
        Sort-Object FullName -Descending | Select-Object -First 1
    if (-not $runtime) { throw 'Visual C++ runtime not found' }
    foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
        Copy-Item (Join-Path $runtime.FullName $dll) $release -Force
    }
    Copy-Item LICENSE "$release/LICENSE.txt" -Force
    Copy-Item THIRD_PARTY_NOTICES.md "$release/THIRD_PARTY_NOTICES.md" -Force
    foreach ($required in 'quota_mate.exe','flutter_windows.dll','sqlite3.dll','quotamate-claude-statusline.exe','data/app.so') {
        if (-not (Test-Path (Join-Path $release $required))) { throw "Missing package component: $required" }
    }
    $version = (Select-String '^version:\s*(\d+\.\d+\.\d+)' pubspec.yaml).Matches[0].Groups[1].Value
    New-Item -ItemType Directory -Force dist/windows | Out-Null
    $zip = Join-Path $projectDirectory "dist/windows/QuotaMate-$version-windows-x64.zip"
    Compress-Archive -Path "$release/*" -DestinationPath $zip -Force
    $iscc = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if (-not $iscc) {
        $innoPath = "${env:ProgramFiles(x86)}/Inno Setup 6/ISCC.exe"
        if (Test-Path $innoPath) { $iscc = Get-Item $innoPath }
    }
    if (-not $iscc) { throw 'Install Inno Setup 6 to build the installer' }
    & $iscc.FullName "/DAppVersion=$version" "/DReleaseDirectory=$release" scripts/windows_installer.iss
    if ($LASTEXITCODE -ne 0) { throw 'Windows installer build failed' }
    $names = @("QuotaMate-$version-windows-x64.zip", "QuotaMate-$version-windows-x64-setup.exe")
    $lines = foreach ($name in $names) {
        $file = Join-Path $projectDirectory "dist/windows/$name"
        '{0}  {1}' -f (Get-FileHash $file -Algorithm SHA256).Hash.ToLowerInvariant(), $name
    }
    $lines | Set-Content dist/windows/SHA256SUMS-windows -Encoding ascii
    # Verify both new outputs before recycling older Windows packages.
    Add-Type -AssemblyName Microsoft.VisualBasic
    Get-ChildItem dist/windows -File | ForEach-Object {
        if ($_.Name -match '^QuotaMate-(\d+\.\d+\.\d+)-windows-x64(?:-setup\.exe|\.zip)$' -and
            [version]$Matches[1] -lt [version]$version) {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($_.FullName,
                [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
        }
    }
    Write-Host "Windows packages ready: dist/windows ($version)"
} finally { Pop-Location }
