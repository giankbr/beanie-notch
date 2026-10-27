# Beanotch for Windows

Windows laptops don't have a notch, so Beanotch for Windows is a small island at the top centre of the screen. Hover it to open the panels. It's built natively with WinUI 3 rather than ported from the Mac app.

> **Status: beta.** It builds on every push (see the Windows workflow in GitHub Actions) but hasn't been tried on real hardware yet. Expect rough edges.

## What's in it

The same panels as the Mac app, in its Studio layout and palette:

| Page | What it does |
|---|---|
| Overview | Health score, CPU, memory, network and disk; cleanup of temp files and browser caches; quick settings. |
| Today | Weather (Open-Meteo), the next events from a calendar's iCal address with a Join button for 19 call services, tasks with reminders, a month view, a focus timer, a countdown timer and world clocks. |
| Prayer | Times for 38 cities (Kemenag, MWL, Umm al-Qura, Egypt, ISNA), the Hijri date, the qibla, and a reminder before each prayer. |
| Now playing | Whatever Windows' media flyout shows, with synced lyrics from LRCLIB and a volume slider. |
| Shelf | Drop files on the island; drag them out into any app later. Screenshots land here too. |
| Clipboard | Text and image history with search and pins. Items password managers mark as private are skipped. |
| AI | Claude Code's tokens and estimated API cost for today, the last 5 hours and the week, with a 7-day chart. |
| Controls | Dark mode, keep awake, mic mute, taskbar auto-hide, desktop icons, hidden files; brightness for the built-in screen and external monitors (DDC/CI); battery; lock, sleep, snip, empty the bin. |
| Tools | An uninstaller that also finds leftover folders, a large-file finder, and the camera. |
| Settings | Theme, accent and font (Segoe UI, Be Vietnam Pro, Inter or Plus Jakarta Sans), which pages show, what the island shows, calendar and clocks, prayer, open at sign-in and updates. |

**The closed island** shows volume, downloads, the current lyric line, the focus timer, meetings and prayers coming up, screenshots, and, in place of the Mac's AirPods card (Windows can't read AirPods' battery): an app starting to use the mic or camera, Bluetooth devices connecting, charging and low battery, and Caps Lock.

Windows doesn't let an unpackaged app read the system calendar, so Today reads a calendar's secret iCal address instead.

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
