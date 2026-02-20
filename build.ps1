Set-StrictMode -Version Latest
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
Push-Location $scriptDir

$odinRoot = (odin root).Trim()
if (-not (Test-Path "$odinRoot/vendor/miniaudio/src")) {
    throw "miniaudio vendor path not found: $odinRoot/vendor/miniaudio/src"
}

& make -C "$odinRoot/vendor/miniaudio/src"

Pop-Location
