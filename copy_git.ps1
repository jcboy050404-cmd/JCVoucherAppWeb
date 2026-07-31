# Workaround: Flutter's child process drops PATH entries, so it can't find git
# even though the system can. Copy the self-contained mingit executables into
# C:\flutter\bin (Flutter's own dir, always on its effective PATH) so flutter's
# internal 'git --version' probe resolves. mingit/cmd is fully self-contained.
$src = 'C:\flutter\bin\mingit\cmd'
$dst = 'C:\flutter\bin'

if (-not (Test-Path $src)) {
    Write-Output "mingit source not found at $src - cannot apply workaround"
    exit 1
}

Write-Output "Copying mingit cmd tools from $src to $dst ..."
$copied = 0
Get-ChildItem -Path $src -File | ForEach-Object {
    $target = Join-Path $dst $_.Name
    if (-not (Test-Path $target)) {
        Copy-Item -Path $_.FullName -Destination $target -Force
        $copied++
    }
}
Write-Output "Copied $copied new file(s) (existing files left in place)."

# Verify git is now directly in C:\flutter\bin
if (Test-Path 'C:\flutter\bin\git.exe') {
    Write-Output 'OK: C:\flutter\bin\git.exe now present'
} else {
    Write-Output 'WARN: git.exe still not in C:\flutter\bin after copy'
}
