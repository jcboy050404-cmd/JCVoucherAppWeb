# Build-only (skip analyze, which hangs in this shell setup). PATH includes
# the copied mingit so flutter's child process can find git.
$paths = @(
    'C:\flutter\bin',
    'C:\Program Files\Git\cmd',
    'C:\Program Files\Git\bin',
    'C:\Program Files\Android\Android Studio\jbr\bin',
    'C:\Windows\System32',
    'C:\Windows',
    'C:\Windows\System32\Wbem',
    'C:\Windows\System32\WindowsPowerShell\v1.0'
)
[Environment]::SetEnvironmentVariable('PATH', ($paths -join ';'), 'Process')
$env:PATH = ($paths -join ';')
Set-Location 'D:\Cap v3\Voucherapp\voucherapps'

Write-Output '=== flutter build apk --release ==='
flutter build apk --release
if ($LASTEXITCODE -ne 0) { throw "build failed (exit $LASTEXITCODE)" }

Write-Output ''
Write-Output '=== verify APK validity + push to website ==='
$apk = 'D:\Cap v3\Voucherapp\voucherapps\build\app\outputs\flutter-apk\app-release.apk'
$dst = 'C:\Users\jccel\Videos\website\downloads\Voucherapp_v1.0.1.apk'
$aapt = 'C:\Users\jccel\AppData\Local\Android\Sdk\build-tools\36.0.0\aapt2.exe'
$badging = & $aapt dump badging $apk 2>&1
if (-not $badging) { throw 'aapt could not read APK - build produced a corrupt file' }
$badging | Select-Object -First 2
Copy-Item $apk $dst -Force
$ha = (Get-FileHash $apk -Algorithm SHA256).Hash
$hb = (Get-FileHash $dst -Algorithm SHA256).Hash
Write-Output "build:   $ha"
Write-Output "website: $hb"
if ($ha -ne $hb) { throw 'hash mismatch - website copy failed' }
Write-Output '=== DONE: valid APK built and pushed to website ==='
