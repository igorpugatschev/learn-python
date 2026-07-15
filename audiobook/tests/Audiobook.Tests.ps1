$modulePath = Join-Path $PSScriptRoot '..\scripts\Audiobook.psm1'
Import-Module $modulePath -Force

Describe 'ConvertFrom-AudiobookMarkdown' {
    It 'removes front matter, fenced code, URLs, and Markdown markers' {
        $markdown = @'
---
title: Exercise 4
source_pages: 42-44
---
# Упражнение 4

Текст про **Python** и `argparse`.

```python
import argparse
```

Подробнее: [документация](https://example.invalid/docs).
'@
        $map = @{ Python = 'Пайтон'; argparse = 'арг парс' }

        $result = ConvertFrom-AudiobookMarkdown -Markdown $markdown -Pronunciation $map

        $result | Should Be "Упражнение 4`n`nТекст про Пайтон и арг парс.`n`nПодробнее: документация."
    }

    It 'rejects unresolved OCR markers' {
        { ConvertFrom-AudiobookMarkdown -Markdown 'Текст [OCR-CHECK]' -Pronunciation @{} } |
            Should Throw 'Найден маркер [OCR-CHECK]'
    }

    It 'rejects a source with no narratable text' {
        $codeOnly = @'
```python
pass
```
'@
        { ConvertFrom-AudiobookMarkdown -Markdown $codeOnly -Pronunciation @{} } |
            Should Throw 'Нет текста для озвучивания'
    }
}

Describe 'Assert-Mp3Metadata' {
    It 'accepts a valid mono 96 kbps MP3' {
        $metadata = [pscustomobject]@{
            FormatName = 'mp3'
            Channels = 1
            DurationSeconds = 12.5
            BitRate = 96000
        }
        Assert-Mp3Metadata -Metadata $metadata
    }

    It 'rejects stereo output' {
        $metadata = [pscustomobject]@{
            FormatName = 'mp3'
            Channels = 2
            DurationSeconds = 12.5
            BitRate = 96000
        }
        { Assert-Mp3Metadata -Metadata $metadata } | Should Throw 'Ожидался один звуковой канал'
    }

    It 'rejects an out-of-range bitrate' {
        $metadata = [pscustomobject]@{
            FormatName = 'mp3'
            Channels = 1
            DurationSeconds = 12.5
            BitRate = 128000
        }
        { Assert-Mp3Metadata -Metadata $metadata } | Should Throw 'Некорректный битрейт'
    }

    It 'rejects a non-MP3 format' {
        $metadata = [pscustomobject]@{
            FormatName = 'wav'
            Channels = 1
            DurationSeconds = 12.5
            BitRate = 96000
        }
        { Assert-Mp3Metadata -Metadata $metadata } | Should Throw 'Ожидался формат MP3'
    }

    It 'rejects a non-positive duration' {
        $metadata = [pscustomobject]@{
            FormatName = 'mp3'
            Channels = 1
            DurationSeconds = 0
            BitRate = 96000
        }
        { Assert-Mp3Metadata -Metadata $metadata } | Should Throw 'Длительность должна быть больше нуля'
    }

    It 'accepts the lower bitrate boundary' {
        $metadata = [pscustomobject]@{
            FormatName = 'mp3'
            Channels = 1
            DurationSeconds = 12.5
            BitRate = 88000
        }
        Assert-Mp3Metadata -Metadata $metadata
    }

    It 'accepts the upper bitrate boundary' {
        $metadata = [pscustomobject]@{
            FormatName = 'mp3'
            Channels = 1
            DurationSeconds = 12.5
            BitRate = 104000
        }
        Assert-Mp3Metadata -Metadata $metadata
    }
}

Describe 'Get-Mp3Metadata' {
    It 'normalizes JSON output from ffprobe' {
        $ffprobePath = Join-Path $TestDrive 'ffprobe-json.ps1'
        @'
Write-Output '{"format":{"format_name":"mp3,mp2","duration":"12.500000","bit_rate":"96000"},"streams":[{"channels":1}]}'
exit 0
'@ | Set-Content -LiteralPath $ffprobePath

        $metadata = Get-Mp3Metadata -Path 'sample.mp3' -FfprobePath $ffprobePath

        $metadata.FormatName | Should Be 'mp3,mp2'
        $metadata.Channels | Should Be 1
        $metadata.DurationSeconds | Should Be 12.5
        $metadata.BitRate | Should Be 96000
    }

    It 'rejects a non-zero ffprobe exit' {
        $ffprobePath = Join-Path $TestDrive 'ffprobe-failure.ps1'
        @'
exit 7
'@ | Set-Content -LiteralPath $ffprobePath

        { Get-Mp3Metadata -Path 'sample.mp3' -FfprobePath $ffprobePath } |
            Should Throw 'ffprobe не смог проверить файл: sample.mp3'
    }
}

Describe 'render_audio.ps1 preflight' {
    It 'keeps existing output when ffmpeg is unavailable' {
        $renderPath = Join-Path $PSScriptRoot '..\scripts\render_audio.ps1'
        $sourcePath = Join-Path $TestDrive 'source.md'
        $outputPath = Join-Path $TestDrive 'existing.mp3'
        Set-Content -LiteralPath $sourcePath -Value '# Тестовый текст'
        Set-Content -LiteralPath $outputPath -Value 'sentinel'
        $originalPath = $env:PATH
        $caught = $null

        try {
            $env:PATH = $TestDrive
            try {
                & $renderPath -InputPath $sourcePath -OutputPath $outputPath
            }
            catch {
                $caught = $_
            }
            if ($null -eq $caught) {
                throw 'Expected render_audio.ps1 to fail when ffmpeg is unavailable'
            }
        }
        finally {
            $env:PATH = $originalPath
        }

        $caught.Exception.Message | Should Match '(?i)ffmpeg'
        (Get-Content -Raw -LiteralPath $outputPath).Trim() | Should Be 'sentinel'
    }
}
