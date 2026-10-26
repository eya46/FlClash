[CmdletBinding()]
param(
  [ValidateSet('android', 'windows')]
  [string[]]$Targets = @('android', 'windows'),

  [ValidateSet('release', 'test')]
  [string[]]$Channels = @('release'),

  [ValidateSet('all', 'arm', 'arm64', 'amd64')]
  [string]$AndroidArch = 'all',

  [ValidateSet('amd64', 'arm64')]
  [string]$WindowsArch = 'amd64',

  [switch]$SkipPubGet,
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = $PSScriptRoot
$DistRoot = Join-Path $RepoRoot 'dist'
$PackageRoot = Join-Path $DistRoot 'packages'
$LocalPropertiesPath = Join-Path $RepoRoot 'android\local.properties'
$LibVersionsPath = Join-Path $RepoRoot 'android\gradle\libs.versions.toml'

function Write-Section {
  param([string]$Message)
  Write-Host ""
  Write-Host "==> $Message" -ForegroundColor Cyan
}

function Normalize-PathValue {
  param([string]$Value)

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return $Value
  }

  return [System.IO.Path]::GetFullPath(($Value -replace '\\\\', '\'))
}

function Get-LocalProperties {
  $result = @{}

  if (-not (Test-Path $LocalPropertiesPath)) {
    return $result
  }

  foreach ($line in Get-Content $LocalPropertiesPath) {
    if ([string]::IsNullOrWhiteSpace($line)) {
      continue
    }
    if ($line.TrimStart().StartsWith('#')) {
      continue
    }
    $parts = $line -split '=', 2
    if ($parts.Length -ne 2) {
      continue
    }
    $result[$parts[0].Trim()] = $parts[1].Trim()
  }

  return $result
}

function Get-NdkVersion {
  if (-not (Test-Path $LibVersionsPath)) {
    throw "Missing $LibVersionsPath"
  }

  $match = Select-String -Path $LibVersionsPath -Pattern '^\s*ndkVersion\s*=\s*"([^"]+)"' | Select-Object -First 1
  if ($null -eq $match) {
    throw "Cannot find ndkVersion in $LibVersionsPath"
  }

  return $match.Matches[0].Groups[1].Value
}

function Resolve-FlutterSdk {
  param([hashtable]$LocalProperties)

  if ($LocalProperties.ContainsKey('flutter.sdk')) {
    $flutterSdk = Normalize-PathValue $LocalProperties['flutter.sdk']
    if (Test-Path $flutterSdk) {
      return $flutterSdk
    }
  }

  $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
  if ($null -ne $flutterCommand) {
    return Split-Path -Parent (Split-Path -Parent $flutterCommand.Source)
  }

  throw 'Cannot resolve Flutter SDK. Set android/local.properties flutter.sdk or add flutter to PATH.'
}

function Add-ToPathFront {
  param([string]$PathItem)

  if ([string]::IsNullOrWhiteSpace($PathItem)) {
    return
  }

  $normalized = Normalize-PathValue $PathItem
  $separator = [System.IO.Path]::PathSeparator
  $pathItems = ($env:Path -split [Regex]::Escape("$separator")) | Where-Object { $_ -ne '' }
  if ($pathItems -contains $normalized) {
    return
  }
  $env:Path = "$normalized$separator$env:Path"
}

function Invoke-External {
  param(
    [string]$Label,
    [string]$Executable,
    [string[]]$Arguments,
    [string]$WorkingDirectory
  )

  $commandLine = @($Executable) + $Arguments
  Write-Section $Label
  Write-Host ($commandLine -join ' ')

  if ($DryRun) {
    return
  }

  Push-Location $WorkingDirectory
  try {
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
      throw "$Label failed with exit code $LASTEXITCODE"
    }
  }
  finally {
    Pop-Location
  }
}

function Ensure-AndroidEnvironment {
  param([hashtable]$LocalProperties)

  $sdkDir = $null
  if ($LocalProperties.ContainsKey('sdk.dir')) {
    $sdkDir = Normalize-PathValue $LocalProperties['sdk.dir']
  } elseif ($env:ANDROID_HOME) {
    $sdkDir = Normalize-PathValue $env:ANDROID_HOME
  }

  if ([string]::IsNullOrWhiteSpace($sdkDir) -or -not (Test-Path $sdkDir)) {
    throw 'Cannot resolve Android SDK. Set android/local.properties sdk.dir or ANDROID_HOME.'
  }

  $ndkVersion = Get-NdkVersion
  $ndkDir = Join-Path $sdkDir "ndk\$ndkVersion"
  if (-not (Test-Path $ndkDir)) {
    throw "Android NDK not found: $ndkDir"
  }

  $env:ANDROID_HOME = $sdkDir
  $env:ANDROID_SDK_ROOT = $sdkDir
  $env:ANDROID_NDK = $ndkDir

  Write-Host "ANDROID_HOME=$sdkDir"
  Write-Host "ANDROID_NDK=$ndkDir"

  if (-not $env:JAVA_HOME) {
    Write-Warning 'JAVA_HOME is not set. Android packaging may fail if Gradle cannot find a JDK.'
  }
}

function Get-SetupArguments {
  param(
    [string]$Target,
    [string]$Channel
  )

  $envName = if ($Channel -eq 'release') { 'stable' } else { 'pre' }
  $args = @('run', 'setup.dart', $Target, '--env', $envName)

  switch ($Target) {
    'android' {
      if ($AndroidArch -ne 'all') {
        $args += @('--arch', $AndroidArch)
      }
    }
    'windows' {
      $args += @('--arch', $WindowsArch)
    }
  }

  return $args
}

function Get-ArtifactFilter {
  param([string]$Target)

  switch ($Target) {
    'android' { return 'FlClash-*-android-*' }
    'windows' { return 'FlClash-*-windows-*' }
    default { throw "Unsupported target: $Target" }
  }
}

function Stage-Artifacts {
  param(
    [string]$Target,
    [string]$Channel
  )

  $filter = Get-ArtifactFilter $Target
  $destination = Join-Path $PackageRoot "$Channel\$Target"

  if ($DryRun) {
    Write-Host "Stage: $filter -> $destination"
    return
  }

  New-Item -ItemType Directory -Force -Path $destination | Out-Null
  Get-ChildItem $destination -File -ErrorAction SilentlyContinue | Remove-Item -Force

  $artifacts = Get-ChildItem $DistRoot -File -Filter $filter | Sort-Object Name
  if ($artifacts.Count -eq 0) {
    Write-Warning "No artifacts matched $filter under $DistRoot"
    return
  }

  foreach ($artifact in $artifacts) {
    Copy-Item -LiteralPath $artifact.FullName -Destination (Join-Path $destination $artifact.Name) -Force
  }

  Write-Host "Staged $($artifacts.Count) file(s) to $destination"
}

$Targets = @($Targets | Select-Object -Unique)
$Channels = @($Channels | Select-Object -Unique)
$LocalProperties = Get-LocalProperties
$FlutterSdk = Resolve-FlutterSdk $LocalProperties
$FlutterBin = Join-Path $FlutterSdk 'bin'
$DartExe = Join-Path $FlutterBin 'dart.bat'
$FlutterExe = Join-Path $FlutterBin 'flutter.bat'

if (-not (Test-Path $DartExe)) {
  throw "dart.bat not found: $DartExe"
}
if (-not (Test-Path $FlutterExe)) {
  throw "flutter.bat not found: $FlutterExe"
}

Add-ToPathFront $FlutterBin

if ($Targets -contains 'android') {
  Ensure-AndroidEnvironment $LocalProperties
}

if (-not $SkipPubGet) {
  Invoke-External `
    -Label 'flutter pub get' `
    -Executable $FlutterExe `
    -Arguments @('pub', 'get') `
    -WorkingDirectory $RepoRoot
}

foreach ($Channel in $Channels) {
  foreach ($Target in $Targets) {
    $setupArgs = Get-SetupArguments -Target $Target -Channel $Channel
    Invoke-External `
      -Label "package $Target ($Channel)" `
      -Executable $DartExe `
      -Arguments $setupArgs `
      -WorkingDirectory $RepoRoot

    Stage-Artifacts -Target $Target -Channel $Channel
  }
}

Write-Section 'Done'
Write-Host "Artifacts root: $PackageRoot"
