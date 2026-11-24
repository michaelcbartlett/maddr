param([string]$Character = 'cop', [string]$Animation = 'walk', [int]$Port = 8766)
$ErrorActionPreference = 'Stop'
$python = (Get-Command python -ErrorAction Stop).Source
$bridge = Join-Path $PSScriptRoot 'bridge.py'
$repository = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$logDirectory = Join-Path $repository '.local'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$arguments = @(('"' + $bridge + '"'), '--open', '--character', $Character, '--animation', $Animation, '--port', $Port)
$logName = if ($Character -eq 'cop' -and $Port -eq 8766) { 'pixelstudio-bridge' } else { "pixelstudio-$Character-$Port" }
Start-Process -FilePath $python -ArgumentList $arguments -WorkingDirectory $repository -WindowStyle Hidden -RedirectStandardOutput (Join-Path $logDirectory "$logName.log") -RedirectStandardError (Join-Path $logDirectory "$logName-error.log")
