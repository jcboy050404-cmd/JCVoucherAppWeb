# Rebuild APK with a fully reconstructed PATH.
# Sets PATH at process scope so child cmd.exe (spawned by flutter.bat) inherits
# flutter, dart, git (including flutter's bundled mingit), and powershell.
$paths = @(
    'C:\flutter\bin',
    'C:\flutter\bin\mingit\cmd',
    'C:\flutter\bin\mingit\mingw64\bin',
    'C:\Program Files\Git\cmd',
    'C:\Program Files\Git\bin',
    'C:\Program Files\Git\mingw64\bin',
    'C:\Program Files\Android\Android Studio\jbr\bin',
    'C:\Windows\System32',
    'C:\Windows',
    'C:\Windows\System32\Wbem',
    'C:\Windows\System32\WindowsPowerShell\v1.0'
)
$joined = ($paths -join ';')
[Environment]::SetEnvironmentVariable('PATH', $joined, 'Process')
$env:PATH = $joined

Set-Location 'D:\Cap v3\Voucherapp\voucherapps'

Write-Output '=== sanity check ==='
Write-Output ("git:     " + ((Get-Command git -ErrorAction SilentlyContinue).Source))
Write-Output ("flutter: " + ((Get-Command flutter -ErrorAction SilentlyContinue).Source))

Write-Output ''
Write-Output '=== flutter analyze (verification) ==='
flutter analyze
if ($LASTEXITCODE -ne 0) {
    Write-Output "analyze failed (exit $LASTEXITCODE) - see errors above"
}

Write-Output ''
Write-Output '=== flutter build apk --release ==='
flutter build apk --release
if ($LASTEXITCODE -ne 0) { throw "build failed (exit $LASTEXITCODE)" }

Write-Output ''
Write-Output '=== verify APK validity + copy to website ==='
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
