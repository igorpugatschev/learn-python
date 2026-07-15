Set-StrictMode -Version Latest

function Assert-AudiobookSource {
    param([Parameter(Mandatory)][string]$Markdown)

    if ([string]::IsNullOrWhiteSpace($Markdown)) {
        throw 'Нет текста для озвучивания'
    }
    if ($Markdown.Contains('[OCR-CHECK]')) {
        throw 'Найден маркер [OCR-CHECK]'
    }
}

function Get-PronunciationMap {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Не найден словарь произношения: $Path"
    }
    return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -AsHashtable
}

function ConvertFrom-AudiobookMarkdown {
    param(
        [Parameter(Mandatory)][string]$Markdown,
        [Parameter(Mandatory)][hashtable]$Pronunciation
    )

    Assert-AudiobookSource -Markdown $Markdown
    $inFrontMatter = $false
    $frontMatterSeen = $false
    $inFence = $false
    $lines = [System.Collections.Generic.List[string]]::new()

    foreach ($rawLine in ($Markdown -split "`r?`n")) {
        $line = $rawLine
        if (-not $frontMatterSeen -and $line -eq '---') {
            $inFrontMatter = $true
            $frontMatterSeen = $true
            continue
        }
        if ($inFrontMatter) {
            if ($line -eq '---') { $inFrontMatter = $false }
            continue
        }
        if ($line -match '^\s*```') {
            $inFence = -not $inFence
            continue
        }
        if ($inFence) { continue }

        $line = $line -replace '^\s{0,3}#{1,6}\s+', ''
        $line = $line -replace '!\[[^\]]*\]\([^\)]+\)', ''
        $line = $line -replace '\[([^\]]+)\]\([^\)]+\)', '$1'
        $line = $line -replace '^\s*[-*+]\s+', ''
        $line = $line -replace '[*_`]', ''
        $lines.Add($line.Trim())
    }

    $text = ($lines -join "`n") -replace "(`n\s*){3,}", "`n`n"
    $text = $text.Trim()
    foreach ($key in ($Pronunciation.Keys | Sort-Object Length -Descending)) {
        $text = [regex]::Replace(
            $text,
            [regex]::Escape([string]$key),
            [string]$Pronunciation[$key],
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
    }
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw 'Нет текста для озвучивания'
    }
    return $text
}

function Get-Mp3Metadata {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$FfprobePath
    )

    $json = & $FfprobePath -v error -show_entries format=format_name,duration,bit_rate `
        -show_entries stream=channels -of json -- $Path
    if ($LASTEXITCODE -ne 0) { throw "ffprobe не смог проверить файл: $Path" }
    $probe = $json | ConvertFrom-Json
    return [pscustomobject]@{
        FormatName = [string]$probe.format.format_name
        Channels = [int]$probe.streams[0].channels
        DurationSeconds = [double]::Parse(
            [string]$probe.format.duration,
            [Globalization.CultureInfo]::InvariantCulture
        )
        BitRate = [int64]$probe.format.bit_rate
    }
}

function Assert-Mp3Metadata {
    param([Parameter(Mandatory)][psobject]$Metadata)

    if ($Metadata.FormatName -notmatch '(^|,)mp3($|,)') { throw 'Ожидался формат MP3' }
    if ($Metadata.Channels -ne 1) { throw 'Ожидался один звуковой канал' }
    if ($Metadata.DurationSeconds -le 0) { throw 'Длительность должна быть больше нуля' }
    if ($Metadata.BitRate -lt 88000 -or $Metadata.BitRate -gt 104000) {
        throw 'Некорректный битрейт'
    }
}

Export-ModuleMember -Function Assert-AudiobookSource, Get-PronunciationMap, `
    ConvertFrom-AudiobookMarkdown, Get-Mp3Metadata, Assert-Mp3Metadata
