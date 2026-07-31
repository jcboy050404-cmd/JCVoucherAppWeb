$sourcePath = "build\windows\x64\runner\Release\*"
$destPath = "C:\Users\jccel\Videos\website\downloads\Voucherapp_v1.0.1.zip"

Write-Host "Zipping Windows Release build to $destPath..."

if (Test-Path $destPath) {
    Remove-Item -Path $destPath -Force
    Write-Host "Removed existing zip file."
}

Compress-Archive -Path $sourcePath -DestinationPath $destPath -Force

Write-Host "Successfully exported Windows app!"
