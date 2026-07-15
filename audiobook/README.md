# Аудиоверсия: пилот

## Предварительные требования

- Microsoft Irina
- ffmpeg
- ffprobe

```powershell
pwsh -File audiobook\scripts\render_audio.ps1 `
  -InputPath audiobook\text\part_02_quick_tasks\04_argparse.md `
  -OutputPath audiobook\output\part_02_quick_tasks\04_argparse.mp3
```

MP3- и WAV-файлы создаются локально и не хранятся в репозитории.
