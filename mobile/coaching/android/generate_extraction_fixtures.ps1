#!/usr/bin/env pwsh
# Synthetic local fixtures only. Requires ffmpeg; no network or real prayer video.
$ErrorActionPreference = 'Stop'
$fixtureDir = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../build/extraction-fixtures'))
New-Item -ItemType Directory -Force -Path $fixtureDir | Out-Null

function Invoke-FixtureEncoder([string[]] $EncoderArgs) {
    & ffmpeg -hide_banner -loglevel error @EncoderArgs
    if ($LASTEXITCODE -ne 0) { throw "ffmpeg failed: $LASTEXITCODE" }
}

Invoke-FixtureEncoder @('-f', 'lavfi', '-i', 'testsrc2=size=1920x1080:rate=30',
    '-t', '8', '-c:v', 'libx264', '-threads', '1', '-preset', 'ultrafast', '-crf', '25',
    '-g', '240', '-pix_fmt', 'yuv420p', '-y', "$fixtureDir/landscape.mp4")
foreach ($rotation in @(90, 270, 180)) {
    $name = if ($rotation -eq 180) { 'rotated180' } else { "portrait$rotation" }
    Invoke-FixtureEncoder @('-i', "$fixtureDir/landscape.mp4", '-c', 'copy',
        '-metadata:s:v:0', "rotate=$rotation", '-y', "$fixtureDir/$name.mp4")
}
Invoke-FixtureEncoder @('-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=2',
    '-t', '3', '-c:v', 'libx264', '-threads', '1', '-preset', 'ultrafast',
    '-g', '6', '-pix_fmt', 'yuv420p', '-y', "$fixtureDir/lowfps.mp4")
Invoke-FixtureEncoder @('-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=30',
    '-t', '3', '-vf', "select='if(lt(t,1),not(mod(n,10)),not(mod(n,3)))'", '-fps_mode', 'vfr',
    '-c:v', 'libx264', '-threads', '1', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p',
    '-y', "$fixtureDir/variablefps.mp4")
Invoke-FixtureEncoder @('-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=30',
    '-t', '3', '-c:v', 'libx264', '-threads', '1', '-preset', 'fast', '-bf', '3',
    '-g', '60', '-pix_fmt', 'yuv420p', '-y', "$fixtureDir/bframes.mp4")
Write-Output "Generated extraction fixtures: $fixtureDir"
