#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$JavaHome = $env:JAVA_HOME,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '../../signing')
)

$ErrorActionPreference = 'Stop'
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if (-not $JavaHome) {
    $JavaHome = Get-ChildItem (Join-Path $PSScriptRoot '../../toolchains') -Directory -Filter 'jdk-*' |
        Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
}
$taskKeytool = Join-Path $JavaHome 'bin/keytool.exe'
if (-not (Test-Path -LiteralPath $taskKeytool)) { throw 'Set -JavaHome to a JDK containing keytool.exe.' }

$taskKeystore = Join-Path $OutputDirectory 'fcitx5-release.p12'
$taskConfigFile = Join-Path $OutputDirectory 'release-signing.json'
$taskCertificate = Join-Path $OutputDirectory 'fcitx5-release.pem'
foreach ($taskPath in @($taskKeystore, $taskConfigFile, $taskCertificate)) {
    if (Test-Path -LiteralPath $taskPath) { throw "Refusing to replace existing signing material: $taskPath" }
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
if ($IsWindows) {
    $taskIdentity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    & icacls.exe $OutputDirectory /inheritance:r /grant:r "${taskIdentity}:(OI)(CI)F" 'SYSTEM:(OI)(CI)F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not restrict signing directory permissions.' }
}

$taskPassword = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
$taskAlias = 'release-' + [Guid]::NewGuid().ToString('N').Substring(0, 16)

function Invoke-SigningKeytool([string[]]$Arguments) {
    $taskStartInfo = [Diagnostics.ProcessStartInfo]::new($taskKeytool)
    $taskStartInfo.UseShellExecute = $false
    $taskStartInfo.CreateNoWindow = $true
    $taskStartInfo.RedirectStandardOutput = $true
    $taskStartInfo.RedirectStandardError = $true
    $taskStartInfo.Environment['FCITX_KEYSTORE_PASSWORD'] = $taskPassword
    foreach ($taskArgument in $Arguments) { $taskStartInfo.ArgumentList.Add($taskArgument) }
    $taskProcess = [Diagnostics.Process]::Start($taskStartInfo)
    $taskStdout = $taskProcess.StandardOutput.ReadToEndAsync()
    $taskStderr = $taskProcess.StandardError.ReadToEndAsync()
    $taskProcess.WaitForExit()
    if ($taskProcess.ExitCode -ne 0) { throw ($taskStdout.Result + $taskStderr.Result) }
}

# Persist the recovery data first, so an interrupted export cannot orphan the private key.
@{
    storeFile = 'fcitx5-release.p12'
    storeType = 'PKCS12'
    keyAlias = $taskAlias
    storePassword = $taskPassword
    keyPassword = $taskPassword
} | ConvertTo-Json | Set-Content -LiteralPath $taskConfigFile -Encoding utf8NoBOM

Invoke-SigningKeytool @(
    '-genkeypair', '-noprompt', '-storetype', 'PKCS12',
    '-keystore', $taskKeystore, '-alias', $taskAlias,
    '-keyalg', 'RSA', '-keysize', '4096', '-sigalg', 'SHA256withRSA',
    '-validity', '10950', '-dname', 'CN=Fcitx5 Personal Release, OU=Android, O=Personal Development',
    '-storepass:env', 'FCITX_KEYSTORE_PASSWORD', '-keypass:env', 'FCITX_KEYSTORE_PASSWORD'
)
Invoke-SigningKeytool @(
    '-exportcert', '-rfc', '-keystore', $taskKeystore, '-alias', $taskAlias,
    '-storepass:env', 'FCITX_KEYSTORE_PASSWORD', '-file', $taskCertificate
)
$taskCert = [Security.Cryptography.X509Certificates.X509Certificate2]::new($taskCertificate)
$taskFingerprint = $taskCert.GetCertHashString([Security.Cryptography.HashAlgorithmName]::SHA256)
@{
    alias = $taskAlias
    sha256 = $taskFingerprint
    notBeforeUtc = $taskCert.NotBefore.ToUniversalTime().ToString('o')
    notAfterUtc = $taskCert.NotAfter.ToUniversalTime().ToString('o')
    publicCertificate = 'fcitx5-release.pem'
} | ConvertTo-Json | Set-Content (Join-Path $OutputDirectory 'certificate-info.json') -Encoding utf8NoBOM
Write-Output "Created signing key: $taskKeystore"
Write-Output "Signing configuration: $taskConfigFile (contains the private password)"
Write-Output "Certificate SHA-256: $taskFingerprint"
