@echo off
REM Delegate to the PowerShell launcher, which loads .env and runs the backend.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run.ps1"
