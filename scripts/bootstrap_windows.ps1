$ErrorActionPreference = 'Stop'

if (-not (Test-Path '.\windows')) {
  Write-Host 'Generating Windows runner...'
  flutter create --project-name aura_hub --org com.ayushnandi --platforms=windows .
}

Write-Host 'Installing dependencies...'
flutter pub get

Write-Host 'Formatting Dart sources...'
dart format .

Write-Host 'Analysing project...'
flutter analyze

Write-Host 'Starting AURA Hub on Windows...'
flutter run -d windows
