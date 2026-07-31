$build = 'D:\Cap v3\Voucherapp\voucherapps\build\app\outputs\flutter-apk\app-release.apk'
$web = 'C:\Users\jccel\Videos\website\downloads\Voucherapp_v1.0.1.apk'
$aapt = 'C:\Users\jccel\AppData\Local\Android\Sdk\build-tools\36.0.0\aapt2.exe'

foreach ($p in @($build, $web)) {
    if (Test-Path $p) {
        $i = Get-Item $p
        Write-Output ("{0}: {1} MB  modified {2}" -f $(if($p -eq $build){'build'}else{'website'}), [math]::Round($i.Length/1MB,2), $i.LastWriteTime)
    } else {
        Write-Output ("{0}: NOT FOUND" -f $p)
    }
}

Write-Output ''
Write-Output '=== Is the build APK valid (not the corrupt one)? ==='
if (Test-Path $build) {
    $b = & $aapt dump badging $build 2>&1
    if ($b) { Write-Output 'build APK: VALID (readable)' ; ($b | Select-Object -First 1) }
    else { Write-Output 'build APK: CORRUPT (aapt cannot read it)' }
}

Write-Output ''
Write-Output '=== Hashes ==='
$ha = (Get-FileHash $build -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
$hb = (Get-FileHash $web -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
Write-Output ("build:   " + $ha)
Write-Output ("website: " + $hb)
if ($ha -and $hb) {
    if ($ha -eq $hb) { Write-Output 'MATCH' } else { Write-Output 'DIFFERENT (website is a different build than the current build/ folder)' }
}
