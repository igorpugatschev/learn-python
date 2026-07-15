[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InputPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$VoiceName = 'Microsoft Irina',
    [ValidateRange(-10, 10)][int]$Rate = 0,
    [ValidatePattern('^96k$')][string]$BitRate = '96k'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Audiobook.psm1') -Force

$inputFile = (Resolve-Path -LiteralPath $InputPath).Path
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$dictionaryPath = Join-Path $repoRoot 'audiobook\pronunciation.json'
$tmpDir = Join-Path $repoRoot 'audiobook\tmp'
$outputFile = [IO.Path]::GetFullPath((Join-Path (Get-Location) $OutputPath))
$outputDir = Split-Path -Parent $outputFile
$token = [guid]::NewGuid().ToString('N')
$wavPath = Join-Path $tmpDir "$token.wav"
$temporaryMp3 = Join-Path $tmpDir "$token.mp3"

$ffmpeg = (Get-Command ffmpeg -ErrorAction Stop).Source
$ffprobe = (Get-Command ffprobe -ErrorAction Stop).Source
$markdown = Get-Content -Raw -LiteralPath $inputFile
$pronunciation = Get-PronunciationMap -Path $dictionaryPath
$narration = ConvertFrom-AudiobookMarkdown -Markdown $markdown -Pronunciation $pronunciation

New-Item -ItemType Directory -Force -Path $tmpDir, $outputDir | Out-Null
Add-Type -AssemblyName System.Speech
$synth = [System.Speech.Synthesis.SpeechSynthesizer]::new()

try {
    $availableVoices = $synth.GetInstalledVoices().VoiceInfo.Name
    if ($VoiceName -notin $availableVoices) { throw "Не найден голос: $VoiceName" }
    $synth.SelectVoice($VoiceName)
    $synth.Rate = $Rate
    $synth.SetOutputToWaveFile($wavPath)
    $synth.Speak($narration)
    $synth.SetOutputToDefaultAudioDevice()

    & $ffmpeg -hide_banner -loglevel error -y -i $wavPath -codec:a libmp3lame `
        -ac 1 -b:a $BitRate $temporaryMp3
    if ($LASTEXITCODE -ne 0) { throw 'FFmpeg не смог создать MP3' }

    $metadata = Get-Mp3Metadata -Path $temporaryMp3 -FfprobePath $ffprobe
    Assert-Mp3Metadata -Metadata $metadata
    Move-Item -Force -LiteralPath $temporaryMp3 -Destination $outputFile
    Remove-Item -Force -LiteralPath $wavPath
    Write-Host "Создан файл: $outputFile"
}
finally {
    $synth.Dispose()
}
