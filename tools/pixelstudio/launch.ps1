$ErrorActionPreference = 'Stop'
$python = (Get-Command python -ErrorAction Stop).Source
$bridge = Join-Path $PSScriptRoot 'bridge.py'
$repository = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$logDirectory = Join-Path $repository '.local'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$arguments = @(('"' + $bridge + '"'), '--open')
Start-Process -FilePath $python -ArgumentList $arguments -WorkingDirectory $repository -WindowStyle Hidden -RedirectStandardOutput (Join-Path $logDirectory 'pixelstudio-bridge.log') -RedirectStandardError (Join-Path $logDirectory 'pixelstudio-bridge-error.log')
