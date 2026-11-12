# Preserve Flutter flags such as --debug; advanced PowerShell parameters consume that flag.
$FlutterArgs = $args
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$originalLocation = Get-Location
$runRoot = $projectRoot

# Dart native hooks and Android NDK tools can fail on Windows paths with spaces.
# SUBST supplies a short path without moving any project files.
if ($projectRoot.Contains(' ')) {
    $existing = subst | Where-Object { $_ -like "*=> $projectRoot" } | Select-Object -First 1
    if ($existing) {
        $runRoot = $existing.Substring(0, 2) + '\'
    } else {
        $letter = @('G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z') | Where-Object { -not (Test-Path "${_}:\") } | Select-Object -First 1
        if (-not $letter) { throw 'No free drive letter. Move the project to a path without spaces.' }
        subst "${letter}:" $projectRoot
        if ($LASTEXITCODE -ne 0) { throw 'Could not create a workspace drive mapping.' }
        $runRoot = "${letter}:\"
        Write-Host "Mapped $projectRoot to $runRoot for Flutter tooling."
    }
}
$localFlutter = Join-Path $runRoot '.tools\flutter\bin\flutter.bat'
$flutterCommand = if (Test-Path $localFlutter) { $localFlutter } else { 'flutter' }
if (Test-Path (Join-Path $runRoot '.tools\pub-cache')) { $env:PUB_CACHE = Join-Path $runRoot '.tools\pub-cache' }
if (Test-Path (Join-Path $runRoot '.tools\android-sdk')) {
    $env:ANDROID_HOME = Join-Path $runRoot '.tools\android-sdk'
    $env:ANDROID_USER_HOME = Join-Path $runRoot '.tools\android-user'
}
$env:GRADLE_USER_HOME = Join-Path $runRoot '.tools\gradle'
if (-not $env:JAVA_HOME -and (Test-Path 'C:\Program Files\Java\jdk-17')) { $env:JAVA_HOME = 'C:\Program Files\Java\jdk-17' }
if (-not (Get-Command git -ErrorAction SilentlyContinue) -and (Test-Path 'D:\app\Git\Git\cmd\git.exe')) { $env:PATH = 'D:\app\Git\Git\cmd;' + $env:PATH }
$env:DEBUG = $null
try {
    Set-Location $runRoot
    & $flutterCommand @FlutterArgs
    $result = $LASTEXITCODE
} finally { Set-Location $originalLocation }
exit $result

