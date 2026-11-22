[CmdletBinding()]
param(
    [string]$Editor = 'E:\repos\video to frames',
    [string]$Stage = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) '.local\pixelstudio-editor')
)
$ErrorActionPreference = 'Stop'
$editorRoot = (Resolve-Path -LiteralPath $Editor).Path
$stageRoot = (Resolve-Path -LiteralPath $Stage).Path
$manifest = Get-Content -LiteralPath (Join-Path $stageRoot 'original-hashes.json') -Raw | ConvertFrom-Json
foreach ($name in @('index.html', 'PIXEL-STUDIO-README.md')) {
    $current = (Get-FileHash -LiteralPath (Join-Path $editorRoot $name) -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($current -ne $manifest.$name) { throw "$name changed after staging. Restage before installing." }
}
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
Copy-Item -LiteralPath (Join-Path $editorRoot 'index.html') -Destination (Join-Path $editorRoot "index.before-godot-character-$stamp.html")
Copy-Item -LiteralPath (Join-Path $editorRoot 'PIXEL-STUDIO-README.md') -Destination (Join-Path $editorRoot "PIXEL-STUDIO-README.before-godot-character-$stamp.md")
foreach ($name in @('index.html', 'PIXEL-STUDIO-README.md', 'godot-character.js', 'Open PixelStudio with Godot.bat')) {
    Copy-Item -LiteralPath (Join-Path $stageRoot $name) -Destination (Join-Path $editorRoot $name)
}
Write-Output "Installed Open Godot character into $editorRoot. Original editor and README backed up with timestamp $stamp."
