# AI Agent Runtime - ????
# ??? .env ???????????????

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$EnvFile = Join-Path $ProjectRoot ".env"
$BackendExe = Join-Path $ProjectRoot "_build\native\debug\build\cmd\main\main.exe"

if (Test-Path $EnvFile) {
    Write-Host "[run] Loading environment from .env file..." -ForegroundColor Cyan
    Get-Content $EnvFile | ForEach-Object {
        $line = $_.Trim()
        if ($line.Length -gt 0 -and -not $line.StartsWith("#")) {
            $idx = $line.IndexOf("=")
            if ($idx -gt 0) {
                $k = $line.Substring(0, $idx).Trim()
                $v = $line.Substring($idx + 1).Trim().Trim('"', "'")
                Set-Item -Path "env:$k" -Value $v
                Write-Host "  [env] $k = ********" -ForegroundColor DarkGray
            }
        }
    }
} else {
    Write-Host "[run] No .env file found" -ForegroundColor Yellow
    Write-Host "[run] Copy .env.example to .env to configure" -ForegroundColor Yellow
}

if ([string]::IsNullOrEmpty($env:DEEPSEEK_API_KEY)) {
    Write-Host "[Error] DEEPSEEK_API_KEY is not set!" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $BackendExe)) {
    Write-Host "[Error] Backend executable not found!" -ForegroundColor Red
    exit 1
}

$model = $env:DEEPSEEK_MODEL
if (-not $model) { $model = "deepseek-chat" }
$port = $env:PORT
if (-not $port) { $port = "8080" }
$dataDir = $env:DATA_DIR
if (-not $dataDir) { $dataDir = "static/data" }
$cors = $env:CORS_ORIGIN
if (-not $cors) { $cors = "*" }

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  AI Agent Runtime - Starting..." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Model:    $model" -ForegroundColor Cyan
Write-Host "  Port:     $port" -ForegroundColor Cyan
Write-Host "  Data dir: $dataDir" -ForegroundColor Cyan
Write-Host "  CORS:     $cors" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

& $BackendExe
$exitCode = $LASTEXITCODE
Write-Host "[run] Backend exited with code: $exitCode" -ForegroundColor Yellow
