@echo off
REM AI Agent Runtime - 启动脚本 (Windows CMD)
REM 从 .env 文件加载环境变量后启动后端服务

setlocal enabledelayedexpansion

REM 加载 .env 文件
if exist ".env" (
    echo [run] Loading environment from .env file...
    for /f "usebackq delims=" %%a in (".env") do (
        set "line=%%a"
        if not "!line!"=="" if "!line:~0,1!" neq "#" (
            for /f "tokens=1,* delims==" %%b in ("!line!") do (
                set "key=%%b"
                set "val=%%c"
                set "val=!val:"=!"
                set "val=!val:'=!"
                set "key=!key: =!"
                if not "!val!"=="" (
                    set "%key%=!val!"
                )
            )
        )
    )
    echo [run] Environment loaded.
)

REM 检查必要变量
if "%DEEPSEEK_API_KEY%"=="" (
    echo [Error] DEEPSEEK_API_KEY is not set!
    echo   Set it in .env file
    exit /b 1
)

REM 检查后端文件
if not exist "_build\native\debug\build\cmd\main\main.exe" (
    echo [Error] Backend executable not found!
    echo   Build it with: moon build --target native --debug
    exit /b 1
)

REM 打印启动信息
echo.
echo ========================================
echo   AI Agent Runtime - Starting...
echo ========================================
echo   Model:    %DEEPSEEK_MODEL%
echo   Port:     %PORT%
echo   Data dir: %DATA_DIR%
echo   CORS:     %CORS_ORIGIN%
echo ========================================
echo.

REM 启动后端
_build\native\debug\build\cmd\main\main.exe
set EXIT_CODE=%ERRORLEVEL%
echo [run] Backend exited with code: %EXIT_CODE%
