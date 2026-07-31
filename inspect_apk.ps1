$apk = 'D:\Cap v3\Voucherapp\voucherapps\build\app\outputs\flutter-apk\app-release.apk'
$web = 'C:\Users\jccel\Videos\website\downloads\Voucherapp_v1.0.1.apk'

Write-Output '=== APK file info ==='
foreach ($p in @($apk, $web)) {
    if (Test-Path $p) {
        $i = Get-Item $p
        Write-Output ("{0}: {1} MB  modified {2}" -f $(if($p -eq $apk){'build'}else{'website'}), [math]::Round($i.Length/1MB,2), $i.LastWriteTime)
    } else {
        Write-Output ("{0}: NOT FOUND" -f $p)
    }
}

Write-Output ''
Write-Output '=== Locate aapt2 in Android SDK ==='
$sdkRoots = @(
    "$env:LOCALAPPDATA\Android\Sdk",
    "$env:ANDROID_HOME",
    "$env:ANDROID_SDK_ROOT",
    'C:\Android\Sdk',
    'C:\Users\jccel\AppData\Local\Android\Sdk'
)
$aapt = $null
foreach ($root in $sdkRoots) {
    $bt = Join-Path $root 'build-tools'
    if (Test-Path $bt) {
        $found = Get-ChildItem $bt -Directory | Sort-Object Name -Descending |
                 Select-Object -First 1 -ExpandProperty FullName
        $candidate = Join-Path $found 'aapt2.exe'
        if (Test-Path $candidate) { $aapt = $candidate; break }
    }
}
if ($aapt) { Write-Output "aapt2 found: $aapt" } else { Write-Output 'aapt2 NOT found in known SDK locations' }

Write-Output ''
Write-Output '=== APK badging (version, SDK, architectures) ==='
if ($aapt) {
    & $aapt dump badging $apk 2>&1 | Select-String -Pattern 'package:|sdkVersion|targetSdkVersion|native-code|uses-gl-es|application-label:'
}

Write-Output ''
Write-Output '=== Native libraries (architectures) inside APK ==='
if ($aapt) {
    & $aapt list $apk 2>&1 | Select-String -Pattern 'lib/.*\.so' | ForEach-Object { ($_ -split '/')[1] } | Sort-Object -Unique
}
