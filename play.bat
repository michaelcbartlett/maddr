@echo off
rem Launch Mad Villain (Godot port). Double-click, or run from a terminal.
rem   play.bat          -> play the game
rem   play.bat editor   -> open the project in the Godot editor
rem   play.bat grapple  -> jump straight into wave 1 with the Shock Grapple (try-out; doesn't save unlocks)
rem Godot is looked up in GODOT_PATH first, then the usual Tools folder.
setlocal
set "GODOT=%GODOT_PATH%"
if "%GODOT%"=="" set "GODOT=%USERPROFILE%\Tools\Godot\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64.exe"
if not exist "%GODOT%" (
  echo Godot not found at "%GODOT%". Set GODOT_PATH to your Godot 4.7 mono exe.
  pause
  exit /b 1
)
if /i "%~1"=="editor" (
  start "" "%GODOT%" --path "%~dp0godot" --editor
) else if /i "%~1"=="grapple" (
  start "" "%GODOT%" --path "%~dp0godot" -- --wave 1 --ammo hook
) else (
  start "" "%GODOT%" --path "%~dp0godot"
)
