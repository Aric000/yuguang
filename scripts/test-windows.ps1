$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
dotnet run --project apps/windows/Yuguang.Tests -c Release
if ($LASTEXITCODE -ne 0) { throw 'Core checks failed' }
dotnet build apps/windows/Yuguang.App -c Release --nologo
if ($LASTEXITCODE -ne 0) { throw 'WPF build failed' }
$exe = Join-Path $root 'apps/windows/Yuguang.App/bin/Release/net10.0-windows/win-x64/Yuguang.exe'
New-Item -ItemType Directory -Path release -Force | Out-Null
$report = Join-Path $root 'release/windows-selftest.json'
$process = Start-Process $exe -ArgumentList @('--demo', '--self-test', '--report', ('"' + $report + '"')) -PassThru
if (!$process.WaitForExit(60000)) { $process.Kill(); throw 'WPF diagnostics timed out' }
if (Test-Path $report) { Get-Content $report }
else { throw 'WPF diagnostics did not produce a report' }
if ($process.ExitCode -ne 0) { throw "WPF diagnostics failed ($($process.ExitCode))" }
