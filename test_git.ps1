$paths = @(
    'C:\Program Files\Git\cmd',
    'C:\Program Files\Git\bin',
    'C:\flutter\bin',
    'C:\flutter\bin\mingit\cmd',
    'C:\Windows\System32',
    'C:\Windows',
    'C:\Windows\System32\WindowsPowerShell\v1.0'
)
[Environment]::SetEnvironmentVariable('PATH', ($paths -join ';'), 'Process')
$env:PATH = ($paths -join ';')

Write-Output '--- PowerShell sees: ---'
(Get-Command git -ErrorAction SilentlyContinue).Source

Write-Output '--- cmd.exe sees (the real test): ---'
& cmd.exe /c "where git 2>&1"
Write-Output ("cmd where exit: " + $LASTEXITCODE)
