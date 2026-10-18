# Create the Android upload signing key and keep signing values in local configuration.
param(
    [string]$Alias = "hiker-circle-upload"
)

$ErrorActionPreference = "Stop"

$workspace = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$androidDirectory = Join-Path $workspace "android"
$keystorePath = Join-Path $androidDirectory "app\hiker-circle-upload.jks"
$propertiesPath = Join-Path $androidDirectory "key.properties"
$certificatePath = Join-Path $androidDirectory "upload-key-certificate.pem"

if ((Test-Path -LiteralPath $keystorePath) -or
    (Test-Path -LiteralPath $propertiesPath)) {
    throw "Upload-key files already exist. They were not overwritten."
}

$keytool = Get-Command keytool.exe -ErrorAction SilentlyContinue
if (-not $keytool) {
    $javaHomeKeytool = if ($env:JAVA_HOME) {
        Join-Path $env:JAVA_HOME "bin\keytool.exe"
    } else {
        $null
    }
    if (-not $javaHomeKeytool -or -not (Test-Path -LiteralPath $javaHomeKeytool)) {
        throw "keytool.exe was not found. Install a JDK or set JAVA_HOME."
    }
    $keytoolPath = $javaHomeKeytool
} else {
    $keytoolPath = $keytool.Source
}

function New-SecurePassword {
    $bytes = [byte[]]::new(36)
    $generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $generator.GetBytes($bytes)
    } finally {
        $generator.Dispose()
    }
    return [Convert]::ToBase64String($bytes).
        Replace("+", "A").
        Replace("/", "B").
        Replace("=", "C")
}

$storePassword = New-SecurePassword
$keyPassword = New-SecurePassword

& $keytoolPath `
    -genkeypair `
    -v `
    -keystore $keystorePath `
    -storetype JKS `
    -storepass $storePassword `
    -keypass $keyPassword `
    -alias $Alias `
    -keyalg RSA `
    -keysize 4096 `
    -validity 10000 `
    -dname "CN=HikerCircle Upload, OU=Mobile, O=HikerCircle, L=Kuala Lumpur, ST=Kuala Lumpur, C=MY"

if ($LASTEXITCODE -ne 0) {
    throw "keytool failed to generate the upload key."
}

$properties = @(
    "storePassword=$storePassword"
    "keyPassword=$keyPassword"
    "keyAlias=$Alias"
    "storeFile=hiker-circle-upload.jks"
) -join [Environment]::NewLine
[System.IO.File]::WriteAllText(
    $propertiesPath,
    $properties + [Environment]::NewLine,
    [System.Text.UTF8Encoding]::new($false)
)

& $keytoolPath `
    -exportcert `
    -rfc `
    -keystore $keystorePath `
    -storepass $storePassword `
    -alias $Alias `
    -file $certificatePath

if ($LASTEXITCODE -ne 0) {
    throw "keytool failed to export the upload certificate."
}

Write-Output "Android upload key created."
Write-Output "Keystore: $keystorePath"
Write-Output "Credentials: $propertiesPath"
Write-Output "Public certificate: $certificatePath"
Write-Output "Back up the keystore and credentials files securely before uploading."
