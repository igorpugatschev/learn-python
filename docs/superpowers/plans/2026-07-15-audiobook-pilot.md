# Audiobook Pilot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Создать локальную учебную MP3-дорожку упражнения 4 с голосом Microsoft Irina и сопровождающий проверенный Markdown.

**Architecture:** PowerShell-модуль преобразует контролируемый Markdown в текст для озвучивания и проверяет метаданные MP3. Командный сценарий синтезирует временный WAV через System.Speech, кодирует его FFmpeg и атомарно публикует локальный MP3 только после проверки через ffprobe.

**Tech Stack:** PowerShell 7.6.3, System.Speech, Pester 3.4.0, FFmpeg/ffprobe 8.1.2, Git.

## Global Constraints

- Пилот охватывает только упражнение 4; остальные упражнения не генерируются до одобрения пилота пользователем.
- Голос: `Microsoft Irina` (`ru-RU`), скорость: `Rate 0`.
- Выход: MP3, один канал, 96 кбит/с.
- Fenced-блоки кода не озвучиваются; перед ними в Markdown должны быть учебные объяснения.
- `[OCR-CHECK]` запрещает генерацию.
- `audiobook/output/` и `audiobook/tmp/` остаются локальными и исключаются из Git.
- В Git попадают только сценарии, тесты, Markdown, словарь произношения, документация и прогресс.
- После каждой завершённой задачи создаётся локальный коммит; `git push` не выполняется без явного запроса.

## File Map

- Create: `audiobook/scripts/Audiobook.psm1` - чистые функции подготовки текста и проверки MP3.
- Create: `audiobook/scripts/render_audio.ps1` - CLI и оркестрация System.Speech/FFmpeg.
- Create: `audiobook/tests/Audiobook.Tests.ps1` - модульные тесты Pester.
- Create: `audiobook/text/part_02_quick_tasks/04_argparse.md` - адаптированный текст и исходные листинги.
- Create: `audiobook/pronunciation.json` - замены для произношения технических терминов.
- Create: `audiobook/README.md` - локальная инструкция запуска.
- Create: `audiobook/progress.md` - состояние пилота и ручная проверка.
- Modify: `.gitignore` - исключение MP3 и временных WAV.

---

### Task 1: Markdown-to-speech conversion

**Files:**
- Create: `audiobook/scripts/Audiobook.psm1`
- Create: `audiobook/tests/Audiobook.Tests.ps1`

**Interfaces:**
- Produces: `Assert-AudiobookSource -Markdown <string>`; throws when `[OCR-CHECK]` exists or text is blank.
- Produces: `Get-PronunciationMap -Path <string>`; returns `[hashtable]`.
- Produces: `ConvertFrom-AudiobookMarkdown -Markdown <string> -Pronunciation <hashtable>`; returns narration `[string]`.

- [ ] **Step 1: Create a RED scaffold and write failing parser tests**

Create `audiobook/scripts/Audiobook.psm1` as a temporary RED scaffold:

```powershell
function ConvertFrom-AudiobookMarkdown {
    param(
        [Parameter(Mandatory)][string]$Markdown,
        [Parameter(Mandatory)][hashtable]$Pronunciation
    )
    throw 'RED: parser is not implemented'
}

Export-ModuleMember -Function ConvertFrom-AudiobookMarkdown
```

Create `audiobook/tests/Audiobook.Tests.ps1`:

```powershell
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
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```powershell
Invoke-Pester audiobook\tests\Audiobook.Tests.ps1
```

Expected: three failed tests with `RED: parser is not implemented`.

- [ ] **Step 3: Implement the parser module**

Create `audiobook/scripts/Audiobook.psm1` with these functions:

```powershell
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

Export-ModuleMember -Function Assert-AudiobookSource, Get-PronunciationMap, ConvertFrom-AudiobookMarkdown
```

- [ ] **Step 4: Run tests and verify GREEN**

Run: `Invoke-Pester audiobook\tests\Audiobook.Tests.ps1`

Expected: `Tests Passed: 3, Failed: 0`.

- [ ] **Step 5: Commit Task 1**

```powershell
git add audiobook/scripts/Audiobook.psm1 audiobook/tests/Audiobook.Tests.ps1
git commit -m "Add audiobook Markdown parser"
```

### Task 2: MP3 metadata validation

**Files:**
- Modify: `audiobook/scripts/Audiobook.psm1`
- Modify: `audiobook/tests/Audiobook.Tests.ps1`

**Interfaces:**
- Produces: `Get-Mp3Metadata -Path <string> -FfprobePath <string>`; returns normalized metadata object.
- Produces: `Assert-Mp3Metadata -Metadata <psobject>`; throws unless format is MP3, channels are 1, duration is positive, and bitrate is 88,000-104,000 bit/s.

- [ ] **Step 1: Add failing metadata tests**

Append to `audiobook/tests/Audiobook.Tests.ps1`:

```powershell
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
```

- [ ] **Step 2: Run tests and verify RED**

Run: `Invoke-Pester audiobook\tests\Audiobook.Tests.ps1`

Expected: three new failures because `Assert-Mp3Metadata` is undefined.

- [ ] **Step 3: Add metadata functions**

Add to `audiobook/scripts/Audiobook.psm1` before `Export-ModuleMember`:

```powershell
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
```

Replace the export line with:

```powershell
Export-ModuleMember -Function Assert-AudiobookSource, Get-PronunciationMap, `
    ConvertFrom-AudiobookMarkdown, Get-Mp3Metadata, Assert-Mp3Metadata
```

- [ ] **Step 4: Run all unit tests**

Run: `Invoke-Pester audiobook\tests\Audiobook.Tests.ps1`

Expected: `Tests Passed: 6, Failed: 0`.

- [ ] **Step 5: Commit Task 2**

```powershell
git add audiobook/scripts/Audiobook.psm1 audiobook/tests/Audiobook.Tests.ps1
git commit -m "Add MP3 metadata validation"
```

### Task 3: Safe render command

**Files:**
- Create: `audiobook/scripts/render_audio.ps1`
- Modify: `audiobook/tests/Audiobook.Tests.ps1`

**Interfaces:**
- Consumes: all exported functions from `Audiobook.psm1`.
- CLI: `render_audio.ps1 -InputPath <md> -OutputPath <mp3> [-VoiceName 'Microsoft Irina'] [-Rate 0] [-BitRate '96k']`.
- Produces: atomically replaced MP3 only after ffprobe validation; retains temporary diagnostics on failure.

- [ ] **Step 1: Add a failing safe-render preflight test**

Append to `audiobook/tests/Audiobook.Tests.ps1`:

```powershell
Describe 'render_audio.ps1 preflight' {
    It 'keeps existing output when ffmpeg is unavailable' {
        $renderPath = Join-Path $PSScriptRoot '..\scripts\render_audio.ps1'
        $sourcePath = Join-Path $TestDrive 'source.md'
        $outputPath = Join-Path $TestDrive 'existing.mp3'
        Set-Content -LiteralPath $sourcePath -Value '# Тестовый текст'
        Set-Content -LiteralPath $outputPath -Value 'sentinel'
        $originalPath = $env:PATH

        try {
            $env:PATH = $TestDrive
            { & $renderPath -InputPath $sourcePath -OutputPath $outputPath } |
                Should Throw '*ffmpeg*'
        }
        finally {
            $env:PATH = $originalPath
        }

        (Get-Content -Raw -LiteralPath $outputPath).Trim() | Should Be 'sentinel'
    }
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```powershell
Invoke-Pester audiobook\tests\Audiobook.Tests.ps1 -TestName 'render_audio.ps1 preflight'
```

Expected: one failed test because `render_audio.ps1` does not exist, so the expected ffmpeg preflight failure is not produced.

- [ ] **Step 3: Implement the rendering script**

Create `audiobook/scripts/render_audio.ps1`:

```powershell
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
```

- [ ] **Step 4: Verify syntax and the focused test GREEN**

Run:

```powershell
$errors = $null
$tokens = $null
[void][Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path audiobook\scripts\render_audio.ps1),
    [ref]$tokens,
    [ref]$errors
)
if ($errors.Count -gt 0) { $errors; exit 1 }
Invoke-Pester audiobook\tests\Audiobook.Tests.ps1 -TestName 'render_audio.ps1 preflight'
```

Expected: exit code 0, no parser errors, and `Tests Passed: 1, Failed: 0`. The existing sentinel output remains unchanged.

- [ ] **Step 5: Run the complete unit suite**

Run:

```powershell
Invoke-Pester audiobook\tests\Audiobook.Tests.ps1
```

Expected: `Tests Passed: 7, Failed: 0`.

- [ ] **Step 6: Commit Task 3**

```powershell
git add audiobook/scripts/render_audio.ps1 audiobook/tests/Audiobook.Tests.ps1
git commit -m "Add safe audiobook render command"
```

### Task 4: Pilot content, documentation, and local-only outputs

**Files:**
- Create: `audiobook/text/part_02_quick_tasks/04_argparse.md`
- Create: `audiobook/pronunciation.json`
- Create: `audiobook/README.md`
- Create: `audiobook/progress.md`
- Modify: `.gitignore`

**Interfaces:**
- `04_argparse.md` is the only pilot input to `render_audio.ps1`.
- `pronunciation.json` is consumed by `Get-PronunciationMap`.
- `progress.md` records `text_ready`, `audio_generated`, and `user_approved` separately.

- [ ] **Step 1: Add local audio paths to `.gitignore`**

Append exactly:

```gitignore

# Locally generated audiobook files
audiobook/output/
audiobook/tmp/
```

Run: `git check-ignore audiobook/output/test.mp3 audiobook/tmp/test.wav`

Expected: both paths are printed.

- [ ] **Step 2: Create the pronunciation dictionary**

Create `audiobook/pronunciation.json`:

```json
{
  "sys.argv": "сис арг ви",
  "argparse": "арг парс",
  "Python": "Пайтон",
  "--help": "дэш дэш хэлп",
  "-h": "дэш аш",
  "PowerShell": "Пауэр Шелл"
}
```

Validate:

```powershell
Get-Content -Raw audiobook\pronunciation.json | ConvertFrom-Json -AsHashtable | Out-Null
```

Expected: exit code 0.

- [ ] **Step 3: Write the complete adapted exercise Markdown**

Create `audiobook/text/part_02_quick_tasks/04_argparse.md` from `materials/book_raw.md:1304-1396`, visually checking PDF pages 42-44. Use this complete pilot content:

```markdown
---
title: Упражнение 4. Аргументы командной строки
part: Часть II. Быстрые задания
source_pages: 42-44
voice: Microsoft Irina
rate: 0
---

# Упражнение 4. Аргументы командной строки

## Зачем нужно это упражнение

В этом упражнении вы исследуете два способа получать аргументы командной строки в Пайтоне. Такое небольшое исследование называют spike, или пробным проектом. Его задача не в том, чтобы сразу создать идеальную программу, а в том, чтобы быстро проверить основные элементы новой библиотеки или инструмента.

На работу предлагается выделить сорок пять минут. Это ограничение не является экзаменом. Оно помогает начать действовать, заметить затруднения и записать, что мешает двигаться дальше. Даже если за это время получился только небольшой рабочий пример, упражнение уже принесло пользу.

## Задача упражнения

Нужно исследовать два подхода. Первый использует список сис арг ви. Второй использует стандартную библиотеку арг парс, которая умеет описывать интерфейс командной строки и автоматически проверять введённые значения.

Программа должна показывать справку по ключу дэш дэш хэлп или дэш аш. Она должна поддерживать как минимум три флага. Флаг не принимает отдельного значения: само его присутствие включает определённый режим. Также нужны как минимум три опции, каждая из которых принимает значение. После опций программа должна собирать позиционные аргументы с именами файлов в отдельный список.

## Как работает решение с argparse

Сначала программа импортирует библиотеку арг парс и создаёт объект парсера. Затем она по очереди описывает позиционный список файлов, три опции со значениями и три логических флага. Метод parse args разбирает фактическую командную строку и возвращает объект, в котором каждому аргументу соответствует атрибут. В конце программа печатает этот объект, чтобы во время исследования было видно, какие значения получены.

```python
import argparse
parser = argparse.ArgumentParser()
parser.add_argument('files', metavar='FILE', nargs='*')
parser.add_argument('-f', '--foo', help='foo help')
parser.add_argument('-b', '--bar', help='bar help')
parser.add_argument('-z', '--baz', help='baz help')
parser.add_argument('-t', '--turn-on', action='store_true')
parser.add_argument('-x', '--exclude', action='store_true')
parser.add_argument('-s', '--start', action='store_true')
args = parser.parse_args()

print(args)
```

Параметр nargs со значением звёздочка означает, что список файлов может содержать ноль или больше элементов. Действие store true задаёт логическое поведение флагов: без флага значение равно false, а при наличии флага становится true. Опции foo, bar и baz сохраняют переданные после них строки. Справку добавляет сам парсер, поэтому отдельный код для неё не нужен.

## Что проверить самостоятельно

Найдите другие библиотеки для обработки командной строки и сравните их с арг парс. Объясните своими словами, чем арг парс удобнее ручной работы со списком сис арг ви. Наконец, запишите, что помогло быстро начать упражнение и какие действия можно улучшить перед следующей задачей.
```

Before saving, compare the embedded listing with `ext_04_argparse/ex04_argparse.py`; they must match. The final file must contain no `[OCR-CHECK]` marker.

Validate:

```powershell
Import-Module audiobook\scripts\Audiobook.psm1 -Force
$path = 'audiobook\text\part_02_quick_tasks\04_argparse.md'
$text = Get-Content -Raw $path
if ($text -match '\[OCR-CHECK\]') { exit 1 }
$narration = ConvertFrom-AudiobookMarkdown -Markdown $text `
    -Pronunciation (Get-PronunciationMap audiobook\pronunciation.json)
if ($narration.Length -lt 1200) { exit 1 }
```

Expected: exit code 0 and narration length of at least 1,200 characters.

- [ ] **Step 4: Add usage and progress documentation**

Create `audiobook/README.md` with the exact pilot command:

```powershell
pwsh -File audiobook\scripts\render_audio.ps1 `
  -InputPath audiobook\text\part_02_quick_tasks\04_argparse.md `
  -OutputPath audiobook\output\part_02_quick_tasks\04_argparse.mp3
```

Document prerequisites `Microsoft Irina`, `ffmpeg`, and `ffprobe`; state that MP3/WAV files are local-only.

Create `audiobook/progress.md`:

```markdown
# Прогресс аудиоверсии

| Часть | Упражнение | Текст | MP3 | Одобрено пользователем |
|---|---|---|---|---|
| II | 4. Аргументы командной строки | готов | не создан | нет |
```

- [ ] **Step 5: Run parser tests and repository checks**

```powershell
Invoke-Pester audiobook\tests\Audiobook.Tests.ps1
git diff --check
git status --short
```

Expected: seven Pester tests pass; no diff errors; only Task 4 files are modified/untracked.

- [ ] **Step 6: Commit Task 4**

```powershell
git add .gitignore audiobook/README.md audiobook/progress.md `
    audiobook/pronunciation.json audiobook/text/part_02_quick_tasks/04_argparse.md
git commit -m "Add adapted argparse audiobook pilot text"
```

### Task 5: Install FFmpeg, generate the pilot, and hand off for listening

**Files:**
- Modify: `audiobook/progress.md`
- Local only: `audiobook/output/part_02_quick_tasks/04_argparse.mp3`
- Local diagnostics: `audiobook/tmp/*`

**Interfaces:**
- Consumes the complete Task 1-4 pipeline.
- Produces a technically verified local MP3 and a progress row awaiting user approval.

- [ ] **Step 1: Install FFmpeg after system approval**

Run with elevated network/system permission:

```powershell
winget install --id Gyan.FFmpeg --exact --accept-package-agreements --accept-source-agreements
```

Expected: installation succeeds. Open a fresh PowerShell process and run:

```powershell
ffmpeg -version
ffprobe -version
```

Expected: both commands report version 8.1.2 or newer.

- [ ] **Step 2: Run the complete automated test suite**

Run: `Invoke-Pester audiobook\tests\Audiobook.Tests.ps1`

Expected: `Tests Passed: 7, Failed: 0`.

- [ ] **Step 3: Generate the pilot MP3**

```powershell
pwsh -File audiobook\scripts\render_audio.ps1 `
  -InputPath audiobook\text\part_02_quick_tasks\04_argparse.md `
  -OutputPath audiobook\output\part_02_quick_tasks\04_argparse.mp3
```

Expected: exit code 0 and `Создан файл: ...04_argparse.mp3`.

- [ ] **Step 4: Independently verify the output**

```powershell
ffprobe -v error -show_entries format=format_name,duration,bit_rate `
  -show_entries stream=channels -of json `
  audiobook\output\part_02_quick_tasks\04_argparse.mp3
```

Expected: `format_name` contains `mp3`, `channels` is `1`, `duration` is greater than `0`, and `bit_rate` is approximately `96000`.

Verify Git exclusion:

```powershell
git check-ignore audiobook\output\part_02_quick_tasks\04_argparse.mp3
git status --short
```

Expected: the MP3 path is printed by `git check-ignore` and does not appear in `git status`.

- [ ] **Step 5: Mark the MP3 as generated and commit progress**

Change only the pilot row in `audiobook/progress.md` to:

```markdown
| II | 4. Аргументы командной строки | готов | создан локально | ожидает проверки |
```

Then run:

```powershell
git add audiobook/progress.md
git commit -m "Record argparse audiobook pilot generation"
```

- [ ] **Step 6: Perform the user listening gate**

Ask the user to listen to the beginning, the explanation immediately before the code listing, and the ending. The user confirms there are no audible Markdown markers, code is not read symbol-by-symbol, the track is not truncated, and the terms `Python`, `argparse`, `sys.argv`, `--help`, and `PowerShell` are understandable.

Stop execution here and wait for the user's complete-pilot feedback. Do not generate any other exercise.

- [ ] **Step 7: Apply user feedback in a follow-up commit**

After the user listens, change `Rate` or `audiobook/pronunciation.json` only when explicitly requested, regenerate the same local MP3, repeat Steps 2-5, and commit text/config changes. When the user approves, set the progress cell to `да` and commit:

```powershell
git add audiobook/progress.md audiobook/pronunciation.json
git commit -m "Approve argparse audiobook pilot"
```

Do not push and do not start exercises 5-52 until that approval is recorded.
