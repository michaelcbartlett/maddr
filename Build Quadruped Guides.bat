@echo off
setlocal
set "SPRITE_PYTHON=%USERPROFILE%\AppData\Local\Comfy-Desktop\ComfyUI-Installs\ComfyUI\ComfyUI\.venv\Scripts\python.exe"
if not exist "%SPRITE_PYTHON%" set "SPRITE_PYTHON=python"
"%SPRITE_PYTHON%" "%~dp0tools\pixelstudio\quadruped_motion.py"
if errorlevel 1 goto failed
"%SPRITE_PYTHON%" "%~dp0tools\pixelstudio\build_h3_attack_dog.py" %*
:failed
set "DOG_RESULT=%ERRORLEVEL%"
pause
exit /b %DOG_RESULT%
