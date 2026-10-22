param([string]$Version = '0.2.1')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
function Test-NativePackage([string]$Exe, [string]$Report) {
    $process = Start-Process $Exe -ArgumentList @('--demo', '--self-test', '--report', ('"' + $Report + '"')) -PassThru
    if (!$process.WaitForExit(60000)) { $process.Kill(); throw 'Packaged WPF diagnostics timed out' }
    if (!(Test-Path $Report)) { throw 'Packaged application did not produce a report' }
    Get-Content $Report
    if ($process.ExitCode -ne 0) { throw 'Packaged application failed diagnostics' }
}
Test-NativePackage (Join-Path $root "release/Yuguang-$Version-windows-x64-portable.exe") (Join-Path $root 'release/windows-portable-check.json')
$destination = Join-Path $env:TEMP ('yuguang-install-check-' + [guid]::NewGuid())
$setup = Start-Process (Join-Path $root "release/Yuguang-$Version-windows-x64-setup.exe") -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', ('/DIR="' + $destination + '"')) -PassThru -Wait
if ($setup.ExitCode -ne 0) { throw 'Installer failed' }
try { Test-NativePackage (Join-Path $destination 'Yuguang.exe') (Join-Path $root 'release/windows-installed-check.json') }
finally {
    $uninstaller = Join-Path $destination 'unins000.exe'
    if (Test-Path $uninstaller) {
        $uninstall = Start-Process $uninstaller -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') -PassThru -Wait
        if ($uninstall.ExitCode -ne 0) { throw 'Uninstall check failed' }
    }
}
