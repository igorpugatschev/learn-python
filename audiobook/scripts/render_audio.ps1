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
$script:RenderScriptRoot = $PSScriptRoot

function Resolve-RenderOutputPath {
    param([Parameter(Mandatory)][string]$OutputPath)

    if ([IO.Path]::IsPathFullyQualified($OutputPath)) {
        return [IO.Path]::GetFullPath($OutputPath)
    }
    return [IO.Path]::GetFullPath((Join-Path (Get-Location) $OutputPath))
}

function Write-AudiobookWave {
    param(
        [Parameter(Mandatory)][string]$Narration,
        [Parameter(Mandatory)][string]$WavPath,
        [Parameter(Mandatory)][string]$VoiceName,
        [Parameter(Mandatory)][int]$Rate,
        [scriptblock]$Synthesize
    )

    if ($null -ne $Synthesize) {
        & $Synthesize $WavPath
        return
    }

    Add-Type -AssemblyName System.Speech
    $synth = [System.Speech.Synthesis.SpeechSynthesizer]::new()
    try {
        $availableVoices = $synth.GetInstalledVoices().VoiceInfo.Name
        if ($VoiceName -notin $availableVoices) { throw "Не найден голос: $VoiceName" }
        $synth.SelectVoice($VoiceName)
        $synth.Rate = $Rate
        $synth.SetOutputToWaveFile($WavPath)
        $synth.Speak($Narration)
        $synth.SetOutputToDefaultAudioDevice()
    }
    finally {
        $synth.Dispose()
    }
}

function Invoke-RenderAudio {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$InputPath,
        [Parameter(Mandatory)][string]$OutputPath,
        [string]$VoiceName = 'Microsoft Irina',
        [ValidateRange(-10, 10)][int]$Rate = 0,
        [ValidatePattern('^96k$')][string]$BitRate = '96k',
        [hashtable]$Pronunciation,
        [scriptblock]$Synthesize
    )

    Import-Module (Join-Path $script:RenderScriptRoot 'Audiobook.psm1') -Force

    $inputFile = (Resolve-Path -LiteralPath $InputPath).Path
    $repoRoot = (Resolve-Path (Join-Path $script:RenderScriptRoot '..\..')).Path
    $dictionaryPath = Join-Path $repoRoot 'audiobook\pronunciation.json'
    $tmpDir = Join-Path $repoRoot 'audiobook\tmp'
    $outputFile = Resolve-RenderOutputPath -OutputPath $OutputPath
    $outputDir = Split-Path -Parent $outputFile
    $token = [guid]::NewGuid().ToString('N')
    $wavPath = Join-Path $tmpDir "$token.wav"

    $ffmpeg = (Get-Command ffmpeg -ErrorAction Stop).Source
    $ffprobe = (Get-Command ffprobe -ErrorAction Stop).Source
    $markdown = Get-Content -Raw -LiteralPath $inputFile
    if ($PSBoundParameters.ContainsKey('Pronunciation')) {
        $pronunciationMap = $Pronunciation
    }
    else {
        $pronunciationMap = Get-PronunciationMap -Path $dictionaryPath
    }
    $narration = ConvertFrom-AudiobookMarkdown -Markdown $markdown -Pronunciation $pronunciationMap

    New-Item -ItemType Directory -Force -Path $tmpDir, $outputDir | Out-Null
    $temporaryMp3 = Join-Path $outputDir ".render-$token.mp3"

    Write-AudiobookWave -Narration $narration -WavPath $wavPath -VoiceName $VoiceName `
        -Rate $Rate -Synthesize $Synthesize

    & $ffmpeg -hide_banner -loglevel error -y -i $wavPath -codec:a libmp3lame `
        -ac 1 -b:a $BitRate $temporaryMp3
    if ($LASTEXITCODE -ne 0) { throw 'FFmpeg не смог создать MP3' }

    $metadata = Get-Mp3Metadata -Path $temporaryMp3 -FfprobePath $ffprobe
    Assert-Mp3Metadata -Metadata $metadata
    Move-Item -Force -LiteralPath $temporaryMp3 -Destination $outputFile
    Remove-Item -Force -LiteralPath $wavPath
    Write-Host "Создан файл: $outputFile"
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-RenderAudio -InputPath $InputPath -OutputPath $OutputPath -VoiceName $VoiceName `
        -Rate $Rate -BitRate $BitRate
}
