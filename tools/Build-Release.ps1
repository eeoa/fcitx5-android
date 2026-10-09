#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ApplicationId,
    [string]$JavaHome = $env:JAVA_HOME,
    [string]$SigningConfig = (Join-Path $PSScriptRoot '../../signing/release-signing.json'),
    [switch]$IncludePlugins,
    [string[]]$GradleArguments = @()
)

$ErrorActionPreference = 'Stop'
$taskRepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$taskToolchainsRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../toolchains'))
if (-not $ApplicationId) {
    $ApplicationId = Get-Content (Join-Path $taskRepoRoot 'gradle.properties') |
        Where-Object { $_ -match '^forkApplicationId=' } |
        ForEach-Object { ($_ -split '=', 2)[1].Trim() }
}
if ($ApplicationId -notmatch '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$' -or
    $ApplicationId -eq 'org.fcitx.fcitx5.android') {
    throw 'Set a valid, independent forkApplicationId before creating a signed release.'
}
if ($GradleArguments -match '^-P(forkApplicationId|signKey)') {
    throw 'Use -ApplicationId and -SigningConfig instead of overriding identity/signing with Gradle arguments.'
}
$SigningConfig = [IO.Path]::GetFullPath($SigningConfig)
$taskSigning = Get-Content -LiteralPath $SigningConfig -Raw | ConvertFrom-Json
$taskStoreFile = [IO.Path]::GetFullPath((Join-Path (Split-Path $SigningConfig) $taskSigning.storeFile))
if (-not (Test-Path -LiteralPath $taskStoreFile) -or
    $taskSigning.storeType -ne 'PKCS12' -or
    -not $taskSigning.keyAlias -or -not $taskSigning.storePassword -or
    $taskSigning.storePassword -ne $taskSigning.keyPassword) {
    throw 'Invalid PKCS12 signing configuration. The upstream signing interface uses one password.'
}
if (-not $JavaHome) {
    $JavaHome = Get-ChildItem $taskToolchainsRoot -Directory -Filter 'jdk-*' |
        Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not (Test-Path -LiteralPath (Join-Path $JavaHome 'bin/java.exe'))) {
    throw 'Set -JavaHome to an installed JDK.'
}

$taskEnvironment = @{
    JAVA_HOME = $JavaHome
    GRADLE_USER_HOME = Join-Path $taskToolchainsRoot 'gradle-user-home'
    SIGN_KEY_FILE = $taskStoreFile
    SIGN_KEY_ALIAS = $taskSigning.keyAlias
    SIGN_KEY_PWD = $taskSigning.storePassword
    SIGN_KEY_STORE_TYPE = $taskSigning.storeType
}
# Native dependencies stay alongside the checkout, without changing the system PATH.
$taskNativePaths = @()
$taskGettextBin = Join-Path $taskToolchainsRoot 'gettext/bin'
if (Test-Path -LiteralPath (Join-Path $taskGettextBin 'msgfmt.exe')) {
    $taskNativePaths += $taskGettextBin
}
$taskCmake = Get-ChildItem (Join-Path $taskToolchainsRoot 'android-sdk/cmake') -Directory -ErrorAction SilentlyContinue |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'bin/ninja.exe') } |
    Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
if ($taskCmake) { $taskNativePaths += Join-Path $taskCmake.FullName 'bin' }
if ($taskNativePaths.Count) {
    $taskEnvironment['PATH'] = ($taskNativePaths -join [IO.Path]::PathSeparator) + [IO.Path]::PathSeparator + $env:PATH
}
$taskEcmDir = Join-Path $taskToolchainsRoot 'ecm/share/ECM/cmake'
if (-not $env:ECM_DIR -and (Test-Path -LiteralPath (Join-Path $taskEcmDir 'ECMConfig.cmake'))) {
    $taskEnvironment['ECM_DIR'] = $taskEcmDir
}
$taskOriginalEnvironment = @{}
foreach ($taskName in $taskEnvironment.Keys) {
    $taskOriginalEnvironment[$taskName] = [Environment]::GetEnvironmentVariable($taskName, 'Process')
    [Environment]::SetEnvironmentVariable($taskName, $taskEnvironment[$taskName], 'Process')
}
Push-Location $taskRepoRoot
try {
    $taskTasks = @(':app:assembleRelease')
    if ($IncludePlugins) { $taskTasks += ':assembleReleasePlugins' }
    & (Join-Path $taskRepoRoot 'gradlew.bat') @taskTasks "-PforkApplicationId=$ApplicationId" @GradleArguments
    if ($LASTEXITCODE -ne 0) { throw "Gradle failed with exit code $LASTEXITCODE." }
} finally {
    Pop-Location
    foreach ($taskName in $taskOriginalEnvironment.Keys) {
        if ($null -eq $taskOriginalEnvironment[$taskName]) {
            Remove-Item -LiteralPath "Env:$taskName" -ErrorAction SilentlyContinue
        } else {
            [Environment]::SetEnvironmentVariable($taskName, $taskOriginalEnvironment[$taskName], 'Process')
        }
    }
}
