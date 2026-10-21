param([string]$Version = '0.2.0')
$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid version' }
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
$publish = Join-Path $root 'release/windows-publish'
dotnet publish apps/windows/Yuguang.App -c Release -r win-x64 --self-contained true -p:Version=$Version -o $publish
if ($LASTEXITCODE -ne 0) { throw 'Publish failed' }
Copy-Item "$publish/Yuguang.exe" "release/Yuguang-$Version-windows-x64-portable.exe" -Force
$iscc = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6/ISCC.exe'
if (!(Test-Path $iscc)) { throw 'Inno Setup 6 is required to build the installer' }
& $iscc "/DAppVersion=$Version" "/DPublishDir=$publish" "/DOutputDir=$root/release" "$PSScriptRoot/windows-installer.iss"
if ($LASTEXITCODE -ne 0) { throw 'Installer build failed' }
Get-ChildItem "release/Yuguang-$Version-windows-x64-*.exe" | ForEach-Object { $hash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant(); "$hash  $($_.Name)" } | Set-Content "release/Yuguang-$Version-windows-x64.sha256" -Encoding ascii
