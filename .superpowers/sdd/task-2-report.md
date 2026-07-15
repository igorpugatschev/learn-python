# Task 2: MP3 Metadata Validation Report

## RED

Command:

```powershell
Invoke-Pester audiobook\tests\Audiobook.Tests.ps1
```

Observed output:

```text
Describing ConvertFrom-AudiobookMarkdown
 [+] removes front matter, fenced code, URLs, and Markdown markers
 [+] rejects unresolved OCR markers
 [+] rejects a source with no narratable text
Describing Assert-Mp3Metadata
 [+] accepts a valid mono 96 kbps MP3
 [-] rejects stereo output
   Expected: the expression to throw an exception with message {Ожидался один звуковой канал}, an exception was raised, message was {The term 'Assert-Mp3Metadata' is not recognized as a name of a cmdlet, function, script file, or executable program.}
 [-] rejects an out-of-range bitrate
   Expected: the expression to throw an exception with message {Некорректный битрейт}, an exception was raised, message was {The term 'Assert-Mp3Metadata' is not recognized as a name of a cmdlet, function, script file, or executable program.}
Tests completed in 509ms
Passed: 4 Failed: 2 Skipped: 0 Pending: 0 Inconclusive: 0
```

The two rejection tests failed because `Assert-Mp3Metadata` was not yet defined. The valid `Should Not Throw` test passed because Pester did not treat the undefined command as a failure for that assertion.

## GREEN

Command:

```powershell
Invoke-Pester audiobook\tests\Audiobook.Tests.ps1
```

Observed output:

```text
Describing ConvertFrom-AudiobookMarkdown
 [+] removes front matter, fenced code, URLs, and Markdown markers
 [+] rejects unresolved OCR markers
 [+] rejects a source with no narratable text
Describing Assert-Mp3Metadata
 [+] accepts a valid mono 96 kbps MP3
 [+] rejects stereo output
 [+] rejects an out-of-range bitrate
Tests completed in 371ms
Passed: 6 Failed: 0 Skipped: 0 Pending: 0 Inconclusive: 0
```

## Complete Suite

Command:

```powershell
Invoke-Pester audiobook\tests
```

Observed output:

```text
Describing ConvertFrom-AudiobookMarkdown
 [+] removes front matter, fenced code, URLs, and Markdown markers
 [+] rejects unresolved OCR markers
 [+] rejects a source with no narratable text
Describing Assert-Mp3Metadata
 [+] accepts a valid mono 96 kbps MP3
 [+] rejects stereo output
 [+] rejects an out-of-range bitrate
Tests completed in 424ms
Passed: 6 Failed: 0 Skipped: 0 Pending: 0 Inconclusive: 0
```

## Implementation Summary

- Added `Get-Mp3Metadata -Path <string> -FfprobePath <string>`.
- Added `Assert-Mp3Metadata -Metadata <psobject>`.
- Exported both functions while preserving all Task 1 exports.
- Added the three exact metadata validation tests from the brief.
- `Get-Mp3Metadata` invokes ffprobe, parses JSON using `ConvertFrom-Json`, normalizes the required fields, and reports a non-zero ffprobe exit code.
- `Assert-Mp3Metadata` enforces MP3 format, one channel, positive duration, and 88,000-104,000 bit/s bitrate.

## Files Changed

- `audiobook/scripts/Audiobook.psm1`
- `audiobook/tests/Audiobook.Tests.ps1`
- `.superpowers/sdd/task-2-report.md`

## Self-Review

- Exact interfaces and exact validation messages from the brief are used.
- Existing Task 1 exports and behavior are preserved.
- No additional public functions, options, abstractions, dependencies, or unrelated refactoring were added.
- Tests cover valid metadata, stereo rejection, and out-of-range bitrate rejection as specified.
- The complete audiobook suite passed 6/6.

## Concerns

- The brief does not add direct tests for `Get-Mp3Metadata`, invalid format, non-positive duration, ffprobe failure, or bitrate boundaries. The implementation follows the exact supplied code and interfaces, but those paths remain untested by this task's prescribed suite.
