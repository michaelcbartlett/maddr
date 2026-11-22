[CmdletBinding()]
param(
    [string]$GodotBinary = $env:GODOT_PATH,
    [switch]$Screenshots
)

$ErrorActionPreference = 'Stop'
if (-not $GodotBinary) {
    $godotCommand = Get-Command godot, godot4, godot_console -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($godotCommand) { $GodotBinary = $godotCommand.Source }
}
if (-not $GodotBinary) {
    $toolsDirectory = Join-Path $env:USERPROFILE 'Tools/Godot'
    $installedGodot = Get-ChildItem -LiteralPath $toolsDirectory -Recurse -Filter '*console.exe' -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1
    if ($installedGodot) { $GodotBinary = $installedGodot.FullName }
}
if (-not $GodotBinary -or -not (Test-Path -LiteralPath $GodotBinary -PathType Leaf)) {
    throw 'Supply -GodotBinary with a Godot 4.7 executable path, or set GODOT_PATH.'
}

$resultsDirectory = Join-Path $PSScriptRoot 'test-results'
New-Item -ItemType Directory -Force -Path $resultsDirectory | Out-Null
Set-Content -LiteralPath (Join-Path $resultsDirectory '.gdignore') -Value ''

function Invoke-GodotCheck([string]$Name, [string[]]$EngineArguments) {
    $logPath = Join-Path $resultsDirectory ($Name + '.log')
    $arguments = @('--path', $PSScriptRoot, '--audio-driver', 'Dummy', '--log-file', $logPath) + $EngineArguments
    & $GodotBinary @arguments
    if ($LASTEXITCODE -ne 0) { throw "$Name failed with exit code $LASTEXITCODE. See $logPath" }
    if (Select-String -LiteralPath $logPath -Pattern '^(SCRIPT ERROR:|ERROR:)' -Quiet) {
        throw "$Name reported an engine/runtime error. See $logPath"
    }
}

Invoke-GodotCheck 'import' @('--headless', '--editor', '--import', '--quit')
Invoke-GodotCheck 'character' @('--headless', '--script', 'res://character/tests/art_test.gd')
Invoke-GodotCheck 'arena' @('--headless', '--script', 'res://game/tests/arena_test.gd')
Invoke-GodotCheck 'selling' @('--headless', '--script', 'res://game/tests/sell_test.gd')
Invoke-GodotCheck 'part-swaps' @('--headless', '--script', 'res://game/tests/swap_test.gd')
Invoke-GodotCheck 'unlocks' @('--headless', '--script', 'res://game/tests/unlocks_test.gd')
Invoke-GodotCheck 'blueprints' @('--headless', '--script', 'res://game/tests/blueprints_test.gd')
Invoke-GodotCheck 'train-heist' @('--headless', '--script', 'res://game/tests/heist_test.gd')
Invoke-GodotCheck 'bank-robbery' @('--headless', '--script', 'res://game/tests/bank_test.gd')
Invoke-GodotCheck 'combat-rules' @('--headless', '--script', 'res://game/tests/combat_rules_test.gd')
Invoke-GodotCheck 'melee' @('--headless', '--script', 'res://game/tests/melee_test.gd')
if ($Screenshots) {
    Invoke-GodotCheck 'rival-scientist' @('--rendering-method', 'gl_compatibility', '--script', 'res://game/tests/rival_scientist_test.gd', '--', '--screenshots')
} else {
    Invoke-GodotCheck 'rival-scientist' @('--headless', '--script', 'res://game/tests/rival_scientist_test.gd')
}
if ($Screenshots) {
    Invoke-GodotCheck 'viper' @('--rendering-method', 'gl_compatibility', '--script', 'res://game/tests/viper_test.gd', '--', '--screenshots')
} else {
    Invoke-GodotCheck 'viper' @('--headless', '--script', 'res://game/tests/viper_test.gd')
}
if ($Screenshots) {
    Invoke-GodotCheck 'reinforcements' @('--rendering-method', 'gl_compatibility', '--script', 'res://game/tests/reinforcements_test.gd', '--', '--screenshots')
} else {
    Invoke-GodotCheck 'reinforcements' @('--headless', '--script', 'res://game/tests/reinforcements_test.gd')
}
if ($Screenshots) {
    Invoke-GodotCheck 'grapple' @('--rendering-method', 'gl_compatibility', '--script', 'res://game/tests/grapple_test.gd', '--', '--screenshots')
} else {
    Invoke-GodotCheck 'grapple' @('--headless', '--script', 'res://game/tests/grapple_test.gd')
}
if ($Screenshots) {
    Invoke-GodotCheck 'enemies' @('--rendering-method', 'gl_compatibility', '--script', 'res://enemies/tests/enemy_art_test.gd', '--', '--screenshots')
} else {
    Invoke-GodotCheck 'enemies' @('--headless', '--script', 'res://enemies/tests/enemy_art_test.gd')
}
if ($Screenshots) {
    Invoke-GodotCheck 'capacitor' @('--rendering-method', 'gl_compatibility', '--script', 'res://game/tests/capacitor_test.gd', '--', '--screenshots')
} else {
    Invoke-GodotCheck 'capacitor' @('--headless', '--script', 'res://game/tests/capacitor_test.gd')
}
if ($Screenshots) {
    Invoke-GodotCheck 'gun-effects' @('--rendering-method', 'gl_compatibility', '--script', 'res://game/tests/effects_test.gd', '--', '--screenshots')
    Invoke-GodotCheck 'gameplay' @('--rendering-method', 'gl_compatibility', '--script', 'res://game/tests/port_test.gd', '--', '--screenshots')
} else {
    Invoke-GodotCheck 'gun-effects' @('--headless', '--script', 'res://game/tests/effects_test.gd')
    Invoke-GodotCheck 'gameplay' @('--headless', '--script', 'res://game/tests/port_test.gd')
}
Write-Host 'Godot port checks passed.'
