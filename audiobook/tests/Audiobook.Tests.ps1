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
        { Assert-Mp3Metadata -Metadata $metadata } | Should Not Throw
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
}
