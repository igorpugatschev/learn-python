# Study Notebook Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the canceled `audiobook` workspace with a compact `notebook` containing only explanatory study notes and an index.

**Architecture:** Move the approved argparse note into a topic-based notebook hierarchy and make `notebook/README.md` the only notebook index. Then remove every speech-specific script, test, configuration file, progress file, and ignore rule while preserving the old design and implementation plan as historical records.

**Tech Stack:** Markdown, PowerShell 7 validation commands, Git.

## Global Constraints

- The final active structure is `notebook/README.md` plus `notebook/part_02_quick_tasks/04_argparse.md`.
- `materials/mentor_plan.md` remains the only learning-progress source; do not create `notebook/progress.md`.
- Preserve the complete Python listing from `ext_04_argparse/ex04_argparse.py` in the note.
- Do not create notes for exercises after exercise 4.
- Do not generate or retain audio files.
- Do not modify `ext_04_argparse/ex04_argparse.py`.
- Preserve the historical audiobook specification and plan under `docs/superpowers/`.
- Do not uninstall FFmpeg from Windows.
- Do not push commits.

---

### Task 1: Move the approved study note into `notebook`

**Files:**
- Create: `notebook/README.md`
- Move: `audiobook/text/part_02_quick_tasks/04_argparse.md` to `notebook/part_02_quick_tasks/04_argparse.md`
- Modify: `notebook/part_02_quick_tasks/04_argparse.md`

**Interfaces:**
- Consumes: the approved note and the canonical listing in `ext_04_argparse/ex04_argparse.py`.
- Produces: a stable notebook index and a note path used by future study-note tasks.

- [ ] **Step 1: Run the structural check and verify RED**

Run from the repository root:

```powershell
$index = 'notebook\README.md'
$note = 'notebook\part_02_quick_tasks\04_argparse.md'
if (-not (Test-Path -LiteralPath $index)) { throw "Missing notebook index: $index" }
if (-not (Test-Path -LiteralPath $note)) { throw "Missing notebook note: $note" }
```

Expected: the command throws `Missing notebook index` because the target structure does not exist yet.

- [ ] **Step 2: Move the note with Git history preserved**

Run:

```powershell
New-Item -ItemType Directory -Force -Path notebook\part_02_quick_tasks | Out-Null
git mv audiobook\text\part_02_quick_tasks\04_argparse.md `
    notebook\part_02_quick_tasks\04_argparse.md
```

Expected: `git status --short` reports the note as a rename.

- [ ] **Step 3: Remove speech-only metadata from the note**

Change the front matter at the beginning of `notebook/part_02_quick_tasks/04_argparse.md` to exactly:

```markdown
---
title: Упражнение 4. Аргументы командной строки
part: Часть II. Быстрые задания
source_pages: 42-44
---
```

Do not change the explanatory body or Python listing in this step.

- [ ] **Step 4: Create the notebook index**

Create `notebook/README.md` with:

```markdown
# Учебный notebook

Этот каталог содержит краткие поясняющие конспекты к упражнениям книги. Они дополняют основной текст и предназначены для повторения после чтения.

Каждый конспект объясняет цель упражнения, разбирает важные конструкции и сохраняет исходный код для одновременного чтения и практики.

## Часть II. Быстрые задания

- [Упражнение 4. Аргументы командной строки](part_02_quick_tasks/04_argparse.md) — страницы 42–44.
```

- [ ] **Step 5: Verify the index, metadata, and canonical code listing**

Run:

```powershell
$indexPath = 'notebook\README.md'
$notePath = 'notebook\part_02_quick_tasks\04_argparse.md'
$index = Get-Content -Raw -LiteralPath $indexPath
$note = Get-Content -Raw -LiteralPath $notePath

if ($index -notmatch 'part_02_quick_tasks/04_argparse\.md') {
    throw 'Notebook index does not link to exercise 4'
}
if ($note -match '(?m)^(voice|rate):' -or $note -match '(?i)audiobook|mp3|speechsynthesizer') {
    throw 'Speech-only metadata or wording remains in the note'
}

$listing = [regex]::Match($note, '(?s)```python\r?\n(.*?)\r?\n```')
if (-not $listing.Success) { throw 'Python listing is missing from the note' }
$expected = (Get-Content -Raw -LiteralPath 'ext_04_argparse\ex04_argparse.py').Trim()
if ($listing.Groups[1].Value.Trim() -cne $expected) {
    throw 'Notebook listing differs from ex04_argparse.py'
}
```

Expected: exit code `0`; the index link exists, audio metadata is absent, and the listing matches exactly.

- [ ] **Step 6: Check and commit Task 1**

Run:

```powershell
git diff --check
git status --short
git add notebook\README.md notebook\part_02_quick_tasks\04_argparse.md
git commit -m "Move argparse study notes to notebook"
```

Expected: `git diff --check` is silent; the commit contains the notebook index and note move only.

---

### Task 2: Remove the canceled audiobook infrastructure

**Files:**
- Delete: `audiobook/scripts/Audiobook.psm1`
- Delete: `audiobook/scripts/render_audio.ps1`
- Delete: `audiobook/tests/Audiobook.Tests.ps1`
- Delete: `audiobook/pronunciation.json`
- Delete: `audiobook/README.md`
- Delete: `audiobook/progress.md`
- Modify: `.gitignore`
- Modify: `docs/superpowers/specs/2026-07-15-audiobook-pilot-design.md`

**Interfaces:**
- Consumes: the notebook paths created by Task 1.
- Produces: an active project with no `audiobook` directory or speech-generation references outside historical documentation.

- [ ] **Step 1: Run the legacy-infrastructure check and verify RED**

Run:

```powershell
$legacy = @(
    'audiobook\scripts\Audiobook.psm1',
    'audiobook\scripts\render_audio.ps1',
    'audiobook\tests\Audiobook.Tests.ps1',
    'audiobook\pronunciation.json',
    'audiobook\README.md',
    'audiobook\progress.md'
)
$remaining = $legacy | Where-Object { Test-Path -LiteralPath $_ }
if ($remaining) { throw "Legacy audiobook files remain: $($remaining -join ', ')" }
```

Expected: the command throws and lists all remaining audio-pilot files.

- [ ] **Step 2: Delete the tracked audio-pilot files**

Run:

```powershell
git rm -r audiobook\scripts audiobook\tests
git rm audiobook\pronunciation.json audiobook\README.md audiobook\progress.md
```

Expected: all listed files are staged for deletion and the now-empty `audiobook` directory disappears.

- [ ] **Step 3: Remove obsolete ignore rules**

Delete this block from `.gitignore`:

```gitignore
# Locally generated audiobook files
audiobook/output/
audiobook/tmp/
```

- [ ] **Step 4: Mark the historical audiobook specification as superseded**

Immediately after the title in `docs/superpowers/specs/2026-07-15-audiobook-pilot-design.md`, add:

```markdown
> **Статус:** пилот завершён без одобрения синтезированного голоса. Аудионаправление отменено; полезный текстовый материал перенесён в учебный `notebook`.
```

Do not rewrite the remaining historical specification or its implementation plan.

- [ ] **Step 5: Verify the clean notebook-only state**

Run:

```powershell
if (Test-Path -LiteralPath 'audiobook') { throw 'The audiobook directory still exists' }
if (-not (Test-Path -LiteralPath 'notebook\README.md')) { throw 'Notebook index is missing' }
if (-not (Test-Path -LiteralPath 'notebook\part_02_quick_tasks\04_argparse.md')) {
    throw 'Exercise 4 note is missing'
}
if (Test-Path -LiteralPath 'notebook\progress.md') { throw 'Duplicate progress file exists' }
if (-not (Test-Path -LiteralPath 'materials\mentor_plan.md')) {
    throw 'Canonical mentor plan is missing'
}

$activeReferences = rg -n --hidden `
    --glob '!.git/**' `
    --glob '!docs/superpowers/**' `
    'audiobook|render_audio|SpeechSynthesizer|\.mp3|\.wav' `
    .gitignore notebook ext_04_argparse 2>$null
if ($LASTEXITCODE -eq 0) { $activeReferences; throw 'Active audio references remain' }
if ($LASTEXITCODE -ne 1) { throw 'Reference scan failed' }

$audioFiles = Get-ChildItem -LiteralPath . -Recurse -Force -File -ErrorAction Stop |
    Where-Object { $_.Extension -in '.mp3', '.wav', '.ogg', '.opus', '.m4a', '.aac', '.flac' }
if ($audioFiles) { $audioFiles.FullName; throw 'Audio artifacts remain' }

git diff --check
```

Expected: all structural checks pass, `rg` returns exit code `1` because no active references match, no audio files are printed, and `git diff --check` is silent.

- [ ] **Step 6: Commit Task 2**

Run:

```powershell
git status --short
git add .gitignore docs\superpowers\specs\2026-07-15-audiobook-pilot-design.md
git commit -m "Remove canceled audiobook infrastructure"
```

Expected: the commit includes the staged deletions, `.gitignore` cleanup, and historical status note.

- [ ] **Step 7: Run final repository verification**

Run:

```powershell
git diff --check HEAD~2..HEAD
git status --short
git log --oneline -2
```

Expected: no diff errors, an empty working tree, and the two migration commits at the top of the log. Do not push.
