# Beanotch for Windows

Windows laptops don't have a notch, so Beanotch for Windows is a small island at the top centre of the screen. Hover it to open the panels. It's built natively with WinUI 3 rather than ported from the Mac app.

> **Status: early preview.** It builds on every push (see the Windows workflow in GitHub Actions) but hasn't been tried on real hardware yet. Expect rough edges.

## What's in it

| Panel | What it does |
|---|---|
| Now playing | Whatever Windows' media flyout shows (Spotify, browsers, Media Player): artwork, progress, play/pause/skip, and synced lyrics from LRCLIB. While music plays, the island shows the current lyric line. |
| Clipboard | Text history, kept in memory. Click an item to copy it again. Items that password managers mark as private are skipped. |
| Prayer | Times worked out on the PC for 38 cities (Kemenag, MWL, Umm al-Qura, Egypt, ISNA), the same calculation as the Mac app. When nothing plays, the island counts down to the next prayer. |
| AI usage | Claude Code's tokens and estimated API cost for today and the week, read from `%USERPROFILE%\.claude\projects`. |

Next: the file shelf, timers and world clocks, a tray icon and a hotkey.

## Layout

```
windows/
  src/Beanotch.Core/        prayer times, lyrics, Claude Code usage; plain .NET, builds and tests on any OS
  src/Beanotch/             the WinUI 3 app (unpackaged, self-contained)
  tests/Beanotch.Core.Tests xUnit tests for the shared code
```

## Install

Download `Beanotch-Setup-x64.exe` (or `-arm64` for Snapdragon laptops) and run it. It installs for your account only, so there's no admin prompt, and it can open Beanotch when you sign in. Nothing else is needed: the .NET runtime and the Windows App SDK come inside.

The installer isn't code-signed yet, so SmartScreen may say "Windows protected your PC". Choose **More info › Run anyway**.

## Build

Needs Windows 10 (19041) or later, the .NET 8 SDK, and the Windows App SDK workload that comes with Visual Studio 2022 ("Windows application development").

```powershell
dotnet test windows/tests/Beanotch.Core.Tests
dotnet publish windows/src/Beanotch/Beanotch.csproj -c Release -r win-x64 -p:Platform=x64 -o out/Beanotch
out/Beanotch/Beanotch.exe
iscc /DAppVersion=0.1.0 /DArch=x64 windows/installer/Beanotch.iss   # → out/Beanotch-Setup-x64.exe (Inno Setup 6)
```

The shared code also builds and tests on macOS or Linux with just the .NET 8 SDK: `dotnet test windows/tests/Beanotch.Core.Tests`.

Settings are stored in `%LOCALAPPDATA%\Beanotch\settings.json`.
