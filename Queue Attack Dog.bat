@echo off
setlocal
set "SPRITE_PYTHON=%USERPROFILE%\AppData\Local\Comfy-Desktop\ComfyUI-Installs\ComfyUI\ComfyUI\.venv\Scripts\python.exe"
if not exist "%SPRITE_PYTHON%" set "SPRITE_PYTHON=python"
"%SPRITE_PYTHON%" "%~dp0tools\pixelstudio\queue_h3_animations.py" --pack "%~dp0export\comfyui\attack-dog" --state-dir "%~dp0.local\h3-attack-dog-queue" --steps 16 --submit %*
set "DOG_RESULT=%ERRORLEVEL%"
pause
exit /b %DOG_RESULT%
