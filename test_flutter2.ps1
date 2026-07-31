$paths = @(
    'C:\Program Files\Git\cmd',
    'C:\Program Files\Git\bin',
    'C:\flutter\bin',
    'C:\Program Files\Android\Android Studio\jbr\bin',
    'C:\Windows\System32',
    'C:\Windows',
    'C:\Windows\System32\Wbem',
    'C:\Windows\System32\WindowsPowerShell\v1.0'
)
[Environment]::SetEnvironmentVariable('PATH', ($paths -join ';'), 'Process')
$env:PATH = ($paths -join ';')
Set-Location 'D:\Cap v3\Voucherapp\voucherapps'

Write-Output '=== Method: invoke flutter via cmd.exe /c (cmd-native process) ==='
& cmd.exe /c "flutter --version" 2>&1 | Select-Object -First 4
Write-Output ("exit: " + $LASTEXITCODE)
