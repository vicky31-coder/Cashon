<#
.SYNOPSIS
    Builds the Inno Setup .exe installer for Cashon.
.DESCRIPTION
    1. Verifies that the Flutter Windows release build exists.
    2. Locates the Inno Setup compiler (ISCC.exe).
    3. Compiles the inno_setup.iss script into a standalone installer .exe.
#>

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$budgetDir = Resolve-Path "$scriptDir\..\.."
$releaseExe = "$budgetDir\build\windows\x64\runner\Release\budget.exe"
$issPath = "$scriptDir\inno_setup.iss"
$outputDir = "$budgetDir\dist"

Write-Host "===============================================" -ForegroundColor Cyan
Write-Host " Cashon Windows Installer Generator (Inno Setup)" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan

# 1. Check if release build exists
if (-not (Test-Path $releaseExe)) {
    Write-Warning "Release build not found at:`n  $releaseExe"
    Write-Host "`nPlease build your Flutter release first by running:" -ForegroundColor Yellow
    Write-Host "  flutter build windows --release`n" -ForegroundColor Green
    Write-Host "Then re-run this script." -ForegroundColor Yellow
    exit 1
}

# 2. Locate ISCC.exe
$isccCandidates = @(
    (Get-Command iscc.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source),
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe"
)

$isccPath = $null
foreach ($path in $isccCandidates) {
    if ($path -and (Test-Path $path)) {
        $isccPath = $path
        break
    }
}

if (-not $isccPath) {
    Write-Error "Could not find Inno Setup compiler (ISCC.exe). Please verify Inno Setup 6 is installed."
    exit 1
}

Write-Host "Using Inno Setup compiler: $isccPath" -ForegroundColor Gray

# 3. Create output directory if it doesn't exist
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# 4. Compile installer
Write-Host "Compiling installer from: $issPath..." -ForegroundColor Green
if ($env:VERSION) {
    & "$isccPath" "/DMyAppVersion=$($env:VERSION)" "$issPath"
} else {
    & "$isccPath" "$issPath"
}

if ($LASTEXITCODE -eq 0) {
    Write-Host "`nInstaller built successfully!" -ForegroundColor Green
    Write-Host "Output directory: $outputDir" -ForegroundColor Cyan
    Get-ChildItem $outputDir -Filter "*.exe" | ForEach-Object {
        Write-Host " -> $($_.Name) ($([math]::Round($_.Length / 1MB, 2)) MB)" -ForegroundColor Yellow
    }
} else {
    Write-Error "Inno Setup compilation failed with exit code $LASTEXITCODE."
}
