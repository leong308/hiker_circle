$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$betaApk = (Resolve-Path 'build/public-beta-source/build/app/outputs/flutter-apk/app-release.apk').Path
$betaSdk = Join-Path $env:LOCALAPPDATA 'Android/Sdk/build-tools/36.0.0'
$betaSignature = & (Join-Path $betaSdk 'apksigner.bat') verify --print-certs $betaApk
if ($LASTEXITCODE -ne 0 -or -not ($betaSignature -match '7e53a63896660a05ba77b11636ae7fcb6f42a26009edb6c14c284d01d5266982')) { throw 'Signature mismatch' }
$betaBadging = & (Join-Path $betaSdk 'aapt.exe') dump badging $betaApk
if ($LASTEXITCODE -ne 0 -or -not ($betaBadging -match "versionName='1.1.0-beta.1'") -or -not ($betaBadging -match "versionCode='3'")) { throw 'Version mismatch' }
$betaPrivateValues = @()
foreach ($betaLine in (Get-Content .env)) {
 if ($betaLine -match '^(GEOAPIFY_API_KEY|GOOGLE_ROUTES_API_KEY|GOOGLE_GEOCODING_API_KEY|OPENROUTESERVICE_API_KEY)=(.+)$') { $betaPrivateValues += $matches[2].Trim().Trim('"', "'") }
}
$betaZip = [System.IO.Compression.ZipFile]::OpenRead($betaApk)
try {
 foreach ($betaEntry in $betaZip.Entries) {
  if ($betaEntry.FullName -match '(?i)\.(jks|keystore|p12)$') { throw 'Signing material found in APK' }
  $betaStream = $betaEntry.Open(); $betaMemory = [System.IO.MemoryStream]::new()
  try { $betaStream.CopyTo($betaMemory); $betaRaw=$betaMemory.ToArray(); $betaAscii=[System.Text.Encoding]::Latin1.GetString($betaRaw); $betaUnicode=[System.Text.Encoding]::Unicode.GetString($betaRaw)
   foreach($betaPrivate in $betaPrivateValues) { if($betaPrivate.Length -gt 8 -and ($betaAscii.Contains($betaPrivate) -or $betaUnicode.Contains($betaPrivate))) { throw ('Original provider credential remains in '+$betaEntry.FullName) } }
  } finally { $betaStream.Dispose(); $betaMemory.Dispose() }
 }
} finally { $betaZip.Dispose() }
$betaHash=(Get-FileHash $betaApk -Algorithm SHA256).Hash.ToLowerInvariant()
@{passed=$true;sha256=$betaHash;version='1.1.0-beta.1';build=3;originalProviderKeysAbsent=$true;signatureVerified=$true} | ConvertTo-Json | Set-Content output/beta/apk-verification.json
Write-Output "APK signature, version and packaged credential audit passed. SHA-256: $betaHash"
