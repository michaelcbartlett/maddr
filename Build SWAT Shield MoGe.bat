@echo off
setlocal
set "SPRITE_PYTHON=%USERPROFILE%\AppData\Local\Comfy-Desktop\ComfyUI-Installs\ComfyUI\ComfyUI\.venv\Scripts\python.exe"
if not exist "%SPRITE_PYTHON%" set "SPRITE_PYTHON=python"
echo Run this after the SWAT animation videos finish. Keep this window open to collect normals.
"%SPRITE_PYTHON%" "%~dp0tools\pixelstudio\queue_h3_moge.py" --pack "%~dp0export\comfyui\swat-shield" --state-dir "%~dp0.local\h3-swat-moge" --submit --wait %*
set "SWAT_RESULT=%ERRORLEVEL%"
pause
exit /b %SWAT_RESULT%
