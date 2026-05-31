# CyberZeus AMS — Release APK build script
# Run from: frontend/
#   .\build_apk.ps1

Write-Host "Cleaning previous build..." -ForegroundColor Cyan
flutter clean

Write-Host "Fetching packages..." -ForegroundColor Cyan
flutter pub get

Write-Host "Building release APK..." -ForegroundColor Cyan
flutter build apk --release --no-tree-shake-icons

$apk = "build\app\outputs\flutter-apk\app-release.apk"
if (Test-Path $apk) {
    $size = [math]::Round((Get-Item $apk).Length / 1MB, 1)
    Write-Host "Done: $apk ($size MB)" -ForegroundColor Green
} else {
    Write-Host "Build failed." -ForegroundColor Red
}
