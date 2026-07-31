$apk = 'D:\Cap v3\Voucherapp\voucherapps\build\app\outputs\flutter-apk\app-release.apk'
$aapt = 'C:\Users\jccel\AppData\Local\Android\Sdk\build-tools\36.0.0\aapt2.exe'

Write-Output '=== Is it a valid ZIP/APK? ==='
try {
    $zip = [System.IO.Compression.ZipFile]::OpenRead($apk)
    Write-Output ("Valid ZIP. Entry count: {0}" -f $zip.Entries.Count)
    $manifest = $zip.GetEntry('AndroidManifest.xml')
    if ($manifest) {
        Write-Output ("AndroidManifest.xml present, size: {0} bytes" -f $manifest.Length)
    } else {
        Write-Output 'AndroidManifest.xml MISSING - APK is corrupt/truncated'
    }
    $zip.Dispose()
} catch {
    Write-Output ("ZIP open FAILED: $($_.Exception.Message)  -- APK is corrupt/truncated")
}

Write-Output ''
Write-Output '=== aapt2 dump (raw, first lines) ==='
$out = & $aapt dump badging $apk 2>&1
if ($out) { $out | Select-Object -First 8 } else { Write-Output '(aapt returned nothing - unreadable)' }

Write-Output ''
Write-Output '=== aapt2 dump xmltree of manifest (head) ==='
$out2 = & $aapt dump xmltree $apk AndroidManifest.xml 2>&1
if ($out2) { $out2 | Select-Object -First 20 } else { Write-Output '(aapt returned nothing)' }
