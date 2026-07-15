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
