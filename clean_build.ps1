$ErrorActionPreference = 'Stop'

# --- Reconstruct PATH for this session AND its child processes ---
# flutter.bat spawns cmd.exe which re-resolves PATH, so the git + powershell
# dirs must be set via [Environment]::SetEnvironmentVariable (process scope)
# which child processes inherit, in addition to $env:PATH.
$paths = @(
    'C:\flutter\bin',
    'C:\flutter\bin\mingit\cmd',
    'C:\flutter\bin\mingit\mingw64\bin',
    'C:\Program Files\Git\cmd',
    'C:\Program Files\Git\bin',
    'C:\Program Files\Android\Android Studio\jbr\bin',
    'C:\Windows\System32',
    'C:\Windows',
    'C:\Windows\System32\Wbem',
    'C:\Windows\System32\WindowsPowerShell\v1.0'
)
$env:PATH = ($paths -join ';')
# Also set process-scope so cmd.exe children inherit it.
[Environment]::SetEnvironmentVariable('PATH', ($paths -join ';'), 'Process')

Set-Location 'D:\Cap v3\Voucherapp\voucherapps'

# Sanity check before the long build.
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'git still not resolvable' }

# Delete the corrupt APK so we don't mistake a stale file for success later.
$apk = 'D:\Cap v3\Voucherapp\voucherapps\build\app\outputs\flutter-apk\app-release.apk'
if (Test-Path $apk) { Remove-Item $apk -Force }

Write-Output '=== STEP 1: flutter clean ==='
flutter clean
Write-Output ''
Write-Output '=== STEP 2: flutter pub get ==='
flutter pub get
Write-Output ''
Write-Output '=== STEP 3: flutter build apk --release ==='
flutter build apk --release
Write-Output ''
Write-Output '=== STEP 4: verify APK validity ==='
if (-not (Test-Path $apk)) { throw 'APK not produced by build' }
$aapt = 'C:\Users\jccel\AppData\Local\Android\Sdk\build-tools\36.0.0\aapt2.exe'
$badging = & $aapt dump badging $apk 2>&1
if (-not $badging) { throw 'aapt could not read APK - still corrupt' }
$badging | Select-Object -First 3
Write-Output ''
Write-Output '=== STEP 5: copy to website + verify hash ==='
$dst = 'C:\Users\jccel\Videos\website\downloads\Voucherapp_v1.0.1.apk'
Copy-Item $apk $dst -Force
$ha = (Get-FileHash $apk -Algorithm SHA256).Hash
$hb = (Get-FileHash $dst -Algorithm SHA256).Hash
Write-Output "build:   $ha"
Write-Output "website: $hb"
if ($ha -ne $hb) { throw 'hash mismatch' }
Write-Output '=== ALL DONE - APK is valid and on website ==='
