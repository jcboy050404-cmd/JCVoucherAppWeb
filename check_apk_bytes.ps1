$apk = 'D:\Cap v3\Voucherapp\voucherapps\build\app\outputs\flutter-apk\app-release.apk'
$i = Get-Item $apk
Write-Output ("File size: {0} bytes ({1} MB)" -f $i.Length, [math]::Round($i.Length/1MB,2))

# Read first 4 bytes. A valid APK (ZIP) starts with PK (0x50 0x4B 0x03 0x04).
$fs = [System.IO.File]::OpenRead($apk)
$buf = New-Object byte[] 4
$n = $fs.Read($buf, 0, 4)
$fs.Close()
$hex = ($buf | ForEach-Object { $_.ToString('X2') }) -join ' '
Write-Output ("First 4 bytes: {0}" -f $hex)
if ($buf[0] -eq 0x50 -and $buf[1] -eq 0x4B) {
    Write-Output 'Signature: PK (valid ZIP header)'
} else {
    Write-Output ('Signature: NOT a ZIP. First bytes = ' + [System.Text.Encoding]::ASCII.GetString($buf))
}

# Also check the last bytes - a complete ZIP ends with the central directory.
# Most importantly, check if the file is mostly empty (zeros).
$fs2 = [System.IO.File]::OpenRead($apk)
$total = $i.Length
$zeroBuf = New-Object byte[] 4096
$nonZero = 0
while ($fs2.Position -lt $total) {
    $got = $fs2.Read($zeroBuf, 0, 4096)
    for ($k=0; $k -lt $got; $k++) { if ($zeroBuf[$k] -ne 0) { $nonZero++ } }
}
$fs2.Close()
Write-Output ("Non-zero bytes: {0} / {1} ({2}%)" -f $nonZero, $total, [math]::Round(100*$nonZero/$total,1))
