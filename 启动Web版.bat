@echo off
REM 本地运行《修仙门派》Web 版
REM Godot Web 导出必须通过 HTTP 访问，双击 index.html（file://）无法运行。
cd /d "%~dp0build"
set PORT=8130

where python >nul 2>nul
if %errorlevel%==0 (
    python serve.py %PORT%
) else (
    "C:\Python314\python.exe" serve.py %PORT%
)
pause
