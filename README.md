# App Installer - myTech.Today

**Version:** 2.0.6 (GUI) / 2.0.2 (CLI)
**Author:** myTech.Today
**License:** All rights reserved

## Overview

The **App Installer** is a comprehensive **cross-platform** PowerShell application installer system for Windows, macOS, and Linux. It provides both a modern **graphical user interface (GUI)** for Windows and a powerful **command-line interface (CLI)** that works on all platforms for installing and managing **271+ essential applications** with real-time status tracking, version detection, and centralized logging.

### Platform Support

- **Windows:** GUI and CLI on the listed Windows 10 releases from 1809 through 22H2, and the Windows 11 client releases in the compatibility contract.
- **macOS:** CLI support on platforms supported by PowerShell Core 7.2.0 through 7.6.9, with Homebrew integration.
- **Linux:** CLI support on platforms supported by PowerShell Core 7.2.0 through 7.6.9, with apt/dnf/pacman/snap integration.

### What's New in 2.0.0

🎉 **Major Cross-Platform Release!**

- ✅ **Cross-Platform CLI:** app-installer-cli.ps1 now works on Windows, macOS, and Linux
- ✅ **Graceful GUI Degradation:** app-installer.ps1 detects platform and offers CLI fallback on non-Windows
- ✅ **Shared Core Module:** New AppInstallerCore.psm1 eliminates code duplication
- ✅ **Dynamic App Registry:** Loads from apps-manifest.json instead of hardcoded arrays
- ✅ **Multi-Package Manager:** Supports winget, brew, apt, dnf, pacman, snap
- ✅ **Platform-Aware Filtering:** Shows only apps available for your platform
- ✅ **Cross-Platform Paths:** Automatic path handling for each OS

See [REFACTORING-SUMMARY.md](other_files/REFACTORING-SUMMARY.md) for complete details.

![App Installer GUI](https://mytech.today/wp-content/uploads/2025/11/install-gui.ps1_.jpeg)

## Features

### Cross-Platform Features (NEW in 2.0.0)

✅ **Multi-Platform Support** - Works on Windows, macOS, and Linux
✅ **Automatic Platform Detection** - Detects OS and selects appropriate package manager
✅ **Package Manager Abstraction** - Supports winget, brew, apt, dnf, pacman, snap
✅ **Platform-Aware App Filtering** - Shows only apps available for your OS
✅ **Cross-Platform Paths** - Automatic path handling for each operating system
✅ **Shared Core Module** - AppInstallerCore.psm1 eliminates code duplication
✅ **Dynamic App Registry** - Loads 271+ apps from apps-manifest.json
✅ **Graceful Degradation** - GUI offers CLI fallback on non-Windows platforms

### GUI Features (app-installer.ps1) - Windows Only

✅ **Modern Windows Forms Interface** - Professional GUI with responsive design and DPI scaling
✅ **Platform Detection** - Detects non-Windows platforms and offers CLI fallback
✅ **Responsive GUI Helper** - Centralized DPI scaling from GitHub for multi-monitor and high-DPI support
✅ **Generic Logging Module** - Centralized logging system with monthly rotation and markdown format
✅ **Real-Time Search & Filter** - Instantly filter 271 applications by name, category, or description
✅ **Real-Time Progress Tracking** - Dynamic progress bar and status updates as you select apps
✅ **Category Organization** - Applications grouped into 13 categories for easy browsing
✅ **Checkbox Selection** - Select individual apps, all apps, or only missing apps
✅ **Export/Import Profiles** - Save and load application selections for backup or deployment
✅ **Uninstall Applications** - Remove installed applications with confirmation and progress tracking
✅ **Live Status Display** - See installation status, version numbers, and progress in real-time
✅ **Saved Queue Recovery** - Saves per-app install progress and requires review plus confirmation before resuming a recovered queue
✅ **HTML Console Output** - Professional, color-coded installation logs in right panel
✅ **Marketing Information** - Company info and service details displayed in HTML panel
✅ **Responsive Layout** - Adapts to different screen sizes and resolutions (VGA to 8K UHD)
✅ **Professional Buttons** - Standard Windows-style buttons with proper spacing

### CLI Features (app-installer-cli.ps1) - All Platforms

✅ **Cross-Platform CLI** - Works on Windows, macOS, and Linux
✅ **Interactive Menu** - User-friendly text-based interface
✅ **Multi-Select** - Select multiple apps with ranges (e.g., "1,3,5-10")
✅ **Category Selection** - Select all apps in a category (e.g., "C:Browsers")
✅ **Version Detection** - Automatically detects installed applications (platform-dependent)
✅ **Selective Installation** - Install individual apps, all apps, or only missing apps
✅ **Generic Logging Module** - Centralized logging with monthly rotation (scriptname-yyyy-MM.md format)
✅ **Centralized Logging** - Platform-specific log paths (Windows: %USERPROFILE%, macOS/Linux: ~/.mytech-today)
✅ **Package Manager Integration** - Leverages platform-specific package managers
✅ **Custom Installers** - Specialized scripts for apps not available via package managers
✅ **Error Handling** - Comprehensive error handling with detailed error messages
✅ **Silent Installation** - Most apps install silently without user interaction
✅ **Administrator Privileges** - Automatic elevation and privilege checking (platform-dependent)
✅ **Automatic Shortcuts** - Creates Start Menu shortcuts for web-based apps (Windows only)
✅ **Monthly Update Scheduling** - Optional Windows task for explicitly selected winget package IDs

#### Optional monthly update scheduling (Windows)

Monthly updates are disabled until you enable them. Run the CLI action to choose package IDs and review the task details:

```powershell
pwsh -NoProfile -File .\app-installer-cli.ps1 -Action EnableMonthlyUpdates
```

The CLI asks for confirmation before creating or replacing its task. The task runs with the current user's highest available privileges and updates only the selected package IDs. Manual all-application updates remain separate. Use `-Action DisableMonthlyUpdates` to remove the application-owned task after confirmation.

#### WinGet agreement handling

Choosing an application requests its installation or update; it does not accept package terms or a source's terms. Interactive install and upgrade commands do not pass `--accept-source-agreements` or `--accept-package-agreements`. WinGet displays the agreement and asks for a decision. If WinGet cannot show its prompt, the command fails with a review message; use the visible WinGet review flow and retry only if you agree. Agreement content is not written to installer log files.

Installed-app and update-discovery queries use `--disable-interactivity` and do not accept source terms while the app is loading or scanning. The monthly task also uses `--disable-interactivity` and never accepts package or source agreements. If a scheduled package update requires agreement review, that package is reported as failed and the run remains incomplete. WinGet may reuse source terms that the user previously accepted through WinGet; the App Installer does not create a separate standing consent for package terms.

## Supported Applications (271+)

**Note:** Application availability varies by platform. The installer automatically filters and shows only apps available for your operating system. Cross-platform package mappings are defined in `apps-manifest.json`.

### Browsers (15)
- Google Chrome, Brave Browser, Firefox, Vivaldi, Opera, LibreWolf, Tor Browser, Waterfox
- Microsoft Edge, Chromium, Arc Browser, Ungoogled Chromium, Midori Browser, Min Browser, Floorp

### Development (26)
- Notepad++, Git, Python, Node.js, Docker Desktop, Sublime Text, Geany, NetBeans IDE
- IntelliJ IDEA Community, FileZilla, Visual Studio Code, Postman, PyCharm Community
- Eclipse IDE, Atom Editor, Brackets, Vagrant, Android Studio, RStudio, Rider
- DataGrip, WebStorm, CLion, GoLand, Vim, CMake, Lazygit

### Productivity (16)
- LibreOffice, Obsidian, Joplin, Foxit PDF Reader, Sumatra PDF, Notion
- 7-Zip, Adobe Acrobat Reader, Apache OpenOffice, Calibre, Zotero, Trello
- WPS Office, PDF24 Creator, Typora, AnyDesk

### Media (26)
- OBS Studio, GIMP, Audacity, Handbrake, OpenShot, ClipGrab, Inkscape, Paint.NET
- Avidemux, MPC-HC, Foobar2000, VLC Media Player, FFmpeg, Krita, OpenToonz
- Kdenlive, Shotcut, darktable, RawTherapee, Spotify, iTunes, AIMP
- DaVinci Resolve, Tenacity, Blender

### Utilities (24)
- AngryIP Scanner, CCleaner, Bitvise SSH Client, Belarc Advisor, O&O ShutUp10
- FileMail Desktop, PowerToys, Everything, Greenshot, Bulk Rename Utility
- Revo Uninstaller, WinDirStat, Core Temp, GPU-Z, CrystalDiskInfo
- Sysinternals Suite, winget Auto-Update, ShareX, Rainmeter, Speccy
- BleachBit, Rufus, Ventoy, HWiNFO

### Security (12)
- Avira Antivirus, Kaspersky Security Cloud, AVG AntiVirus Free, Avast Free Antivirus
- Malwarebytes, Bitwarden, 1Password, LastPass, Dashlane, Sophos Home
- KeePassXC, NordPass, Proton Pass

### Communication (11)
- Telegram Desktop, Signal, Thunderbird, Discord, Slack, Zoom, Microsoft Teams
- Skype, WhatsApp Desktop, Viber, Element

### 3D & CAD (10)
- Blender, FreeCAD, LibreCAD, KiCad, OpenSCAD, Wings 3D, Sweet Home 3D
- Dust3D, MeshLab, Slic3r

### Networking (9)
- Nmap, Wireshark, Zenmap, PuTTY, Advanced Port Scanner, Advanced IP Scanner
- Fing CLI, GlassWire, NetLimiter, TCPView

### Runtime (7)
- Java Runtime Environment, .NET Desktop Runtime 6, .NET Desktop Runtime 8
- Visual C++ Redistributable, Go Programming Language, Rust, PHP

### Writing (9)
- Trelby, KIT Scenarist, Storyboarder, Manuskript, yWriter, Celtx
- bibisco, Scribus, FocusWriter

### Gaming (7)
- Steam, Epic Games Launcher, GOG Galaxy, EA App, Ubisoft Connect
- Battle.net, Itch.io

### Cloud Storage (6)
- Google Drive, Dropbox, OneDrive, MEGA, pCloud, Sync.com

### Remote Desktop (7)
- TeamViewer, AnyDesk, Chrome Remote Desktop, TightVNC, RustDesk
- UltraVNC, Parsec

### Backup (7)
- Veeam Agent FREE, EaseUS Todo Backup Free, Duplicati, Cobian Backup
- FreeFileSync, Syncthing, Macrium Reflect Free

### Education (7)
- Anki, GeoGebra, Stellarium, MuseScore, Moodle Desktop, Scratch Desktop
- Celestia

### Finance (6)
- GnuCash, HomeBank, Money Manager Ex, KMyMoney, Skrooge
- Firefly III Desktop

### Shortcuts & Maintenance (7)
- Grok AI (Desktop & Start Menu)
- ChatGPT (Desktop & Start Menu)
- dictation.io (Desktop & Start Menu)
- Uninstall McAfee Products
- PowerToys, AutoHotkey, Everything

## Requirements

The single compatibility source is [`compatibility.json`](compatibility.json). It defines Windows compatibility targets, editions, architecture, PowerShell engine bounds, runtime prerequisites, vendor lifecycle notes, and recovery behavior. The README table below is checked against that file by `tests/test-compatibility-contract.ps1`. The [PowerShell engine compatibility inventory](other_files/powershell-engine-compatibility.md) records reachable source paths, API differences, safeguards, and validation limits.

### Windows
- **Operating system:** Windows 10 x64 Home or Pro, using an exact release/build pair listed from version 1809 through 22H2, or Windows 11 25H2 build 26200 or Windows 11 26H2 build 26300, Home or Pro, x64. The listed Windows 11 releases must still be within their end-of-servicing dates. Windows 10 Home and Pro reached Microsoft end of support on 2025-10-14; App Installer compatibility does not provide Windows security updates.
- **Windows PowerShell:** Desktop edition 5.1. It supports the GUI and CLI. The GUI requires .NET Framework 4.7.2 or later, registry release value 461808 or later.
- **PowerShell Core:** Versions 7.2.0 through 7.6.9 are compatibility targets for the CLI. The GUI also requires Windows Desktop runtime 10 and successful loads of `System.Windows.Forms`, `System.Drawing`, and `System.Web`. The compatibility boundary test covers 7.2.0; native PowerShell 7.2 and Windows 10 runtime evidence was not available for this update. PowerShell 7.2 is retired by Microsoft, and this technical compatibility target does not imply it receives security updates.
- **Host preflight:** One shared result records the Windows product family, release, build, edition, host architecture, GUI runtime requirements, WinGet availability, and selected PowerShell artifact architecture. It rejects unavailable OS metadata and any host or artifact architecture mismatch before runtime provisioning or package setup.
- **WinGet:** Optional for host support. If WinGet is missing, the host and CLI preflight remain valid and the CLI reports the missing package manager before package actions. Microsoft documents WinGet on Windows 10 version 1809 or later, Windows 11, and Windows Server 2025 with Desktop Experience. This App Installer release has no verified Server package workflow, so every Server SKU remains outside the support matrix.
- **Windows 10 WinGet bootstrap:** The bootstrap guard accepts Windows 10 x64 client builds 17763 through 21999. WinGet remains optional and its availability does not establish OS or package workflow evidence.
- **Runtime artifact architecture:** The only provisioned runtime artifact is PowerShell Core 7.6.9 for Windows x64. The preflight selects it only for a supported x64 host and blocks an unknown host architecture or artifact mismatch. It never chooses an x64 archive for x86 or ARM64.
- **GUI startup gate:** Before loading GUI-only helpers or constructing a form, the installer validates the Windows release, PowerShell edition and version, x64 process architecture, STA apartment, runtime prerequisite, and required assemblies. If GUI capability is unavailable and the supported CLI can run, it starts the CLI once with the original CLI arguments and returns the CLI process exit code. The capability check reports status; provisioning is a separate consent-gated step. In GUI mode, `-WhatIf` reports the preflight result and exits without opening the GUI. CLI mode retains the CLI's dry-run preview.
- **Launcher behavior:** `install.bat` is the source-script setup entry point. It starts the shared runtime resolver, which checks fixed PowerShell installation locations, registered PowerShell Core installations, and the current-user Microsoft.PowerShell package registration. It prefers any compatible PowerShell Core from 7.2.0 through 7.6.9 when its GUI requirements pass, then Windows PowerShell 5.1. Use `-ForceCLI` to select `app-installer-cli.ps1` directly; CLI mode accepts Windows PowerShell 5.1 or PowerShell Core 7.2.0 through 7.6.9. A safe preflight failure can move to the next compatible engine. Once the installer starts, it never retries application work in another engine. The resolver does not search PATH; its consent-gated provisioning plan remains pinned to PowerShell Core 7.6.9. The batch wrapper returns without waiting by default; add `-KeepConsoleOpen` to keep its console open after a started PowerShell stage finishes.
- **Executable distribution:** When a release has been published, use only its versioned `AppInstaller-<GUI-version>-win-x64.exe` asset together with the matching checksum and release manifest. The versioned release package is defined as an unsigned IExpress launcher and does not bundle PowerShell. The retired legacy executable records below are not current release downloads.
- **Unsupported:** Windows 10 before version 1809/build 17763, Windows Server, Enterprise and Education editions, x86, ARM64, Windows releases absent from the matrix, and PowerShell Core versions below 7.2.0 or above 7.6.9. The launcher exits before package-manager calls or persistent changes and prints the minimum requirement and recovery steps.
- **Optional runtime installation:** Startup checks every discovered PowerShell candidate and its required CLI or GUI capabilities before offering provisioning. If no installed candidate can run the CLI, the installer presents the exact plan and asks for explicit consent before offering a current-user PowerShell Core 7.6.9 ZIP install from the GitHub release URL and SHA-256 pin in `compatibility.json`. The ZIP is verified before extraction, and the extracted executable is signature-checked and revalidated from its exact path before launch. The install does not require administrator privileges and does not change PATH, the default engine, or another PowerShell installation. GUI-only capability gaps use an already compatible CLI when available. If no PowerShell engine can start the preflight launcher, install.bat prints the pinned source and recovery steps without downloading or installing anything. Preview the provisioning decision with `powershell.exe -NoProfile -File .\tools\Install-CompatiblePowerShell.ps1 -WhatIf`; rerun without `-WhatIf` to review the plan and decide whether to proceed.
- **Verification:** `tests/test-compatibility-contract.ps1` covers Windows 10 release/build pairs, the Windows 10 1809 floor, PowerShell Core 7.2.0 and 8.0.0 boundaries, editions, architecture, runtime, and Windows 11 end-of-servicing boundaries with mocked metadata. It does not provide native Windows 10 or PowerShell 7.2 runtime evidence. `tests/test-executable-metadata.ps1` inspects the current versioned executable and confirms metadata writes reject both retired paths. `tests/test-executable-build.ps1` validates the generated versioned executable and its provenance; `tests/test-executable-resource-update.ps1` tests cabinet replacement on a temporary copy of the current executable.

Microsoft sources: [supported Windows client versions](https://learn.microsoft.com/en-us/windows/release-health/supported-versions-windows-client), [.NET Framework system requirements](https://learn.microsoft.com/en-us/dotnet/framework/get-started/system-requirements), [Windows PowerShell](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-windows-powershell?view=powershell-7.6), [PowerShell 7 support lifecycle](https://learn.microsoft.com/en-us/powershell/scripting/install/powershell-support-lifecycle?view=powershell-7.6), [PowerShell 7.6.9 release assets](https://github.com/PowerShell/PowerShell/releases/tag/v7.6.9), and [WinGet availability and system requirements](https://learn.microsoft.com/en-us/windows/package-manager/winget/).

### Compatibility source review

Manually compare the Windows client lifecycle, PowerShell support lifecycle, and pinned PowerShell release sources at least every 180 days and before a versioned release. The current recorded review date is `2026-11-07` in `compatibility.json`. Run `pwsh -NoProfile -File .\tools\Test-CompatibilityReview.ps1` for an offline age check; stale dates produce a warning in local output and CI. The versioned release workflow runs the same check with `-RequireFresh` and stops when the review is overdue. Update `lastReviewed` manually only after checking the official [Windows client lifecycle](https://learn.microsoft.com/en-us/windows/release-health/supported-versions-windows-client), [PowerShell support lifecycle](https://learn.microsoft.com/en-us/powershell/scripting/install/powershell-support-lifecycle?view=powershell-7.6), and [pinned PowerShell release](https://github.com/PowerShell/PowerShell/releases/tag/v7.6.9). The checker makes no network requests and never writes to the contract; source changes remain a human review.

### macOS
- **Operating system and PowerShell:** Use a macOS version supported by the installed PowerShell Core release.
- **PowerShell:** Version 7.2.0 through 7.6.9 (install via: `brew install --cask powershell`)
- **Package Manager:** Homebrew (install from https://brew.sh)
- **Privileges:** sudo access recommended for system-wide installations
- **Note:** GUI mode not available - use CLI mode (`app-installer-cli.ps1`)

### Linux
- **Operating system and PowerShell:** Use a Linux distribution and architecture supported by the installed PowerShell Core release.
- **PowerShell:** Version 7.2.0 through 7.6.9 (see Microsoft's [PowerShell installation guidance](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-linux?view=powershell-7.6))
- **Package Manager:** apt, dnf, pacman, or snap (automatically detected)
- **Privileges:** sudo/root access recommended for system-wide installations
- **Note:** GUI mode not available - use CLI mode (`app-installer-cli.ps1`)

The CLI preserves the existing OS and package-manager filters in `platform-detect.ps1` and `apps-manifest.json`. Those filters control package availability; they do not expand the PowerShell engine contract.

### CLI container image

The CLI-only image in `Dockerfile.cli` uses Microsoft's .NET 10 Ubuntu runtime and installs PowerShell Core 7.6.9 for `amd64` or `arm64`. It checks the official release archive's SHA-256 before extraction. Build the image from the repository root:

```bash
docker build -f Dockerfile.cli -t app-installer-cli .
```

### Building the Windows executable

The reproducible build follows the unsigned x64 IExpress contract in `compatibility.json`. It generates a fresh launcher from a checked-in template using the pinned, Microsoft-signed Windows IExpress tool, then writes a versioned output under `builds/generated/`. No executable seed is checked in. Run it from a clean or reviewed source checkout on Windows 11 build 26300 x64 or Windows Server 2025 build 26100 x64 with PowerShell Core 7.6.9, .NET runtime 10.0.14, and the pinned IExpress, MakeCab, and Expand tools recorded in `tools/installer-exe-build.json`:

```powershell
pwsh -NoProfile -File .\tools\Build-InstallerExe.ps1
```

The default output is `builds/generated/AppInstaller-<GUI-version>-win-x64.exe`, with an adjacent `.build.json` provenance file. `.gitignore` excludes `builds/generated/`, so a local build does not become a checked-in or published release. Pass `-OutputPath` to choose another destination while keeping the versioned filename. Both retired executable paths remain reserved as output paths even though their files have been removed. Existing artifacts and provenance files are never overwritten. `-WhatIf` runs the pinned source and toolchain preflight without creating output files.

`tools/installer-exe-build.json` pins the host, PowerShell distribution, .NET runtime files, Roslyn compiler assemblies, IExpress, MakeCab, and Expand by version, SHA-256, and signer where applicable. To acquire a missing prerequisite, use only the official URLs in that file. Verify the PowerShell archive against `distributionSha256` before extraction, then verify the extracted `pwsh.exe` hash and Microsoft signature. Verify the .NET runtime installer against `installerSha512` and its Authenticode signature before installing it. IExpress, MakeCab, and Expand are Windows components and are checked by hash and Microsoft signature. The builder does not download or install build dependencies. Roslyn is included in the pinned PowerShell distribution, so a separate .NET SDK is not required. The provenance file records the source commit and worktree status, hashes of build inputs, toolchain observations, payload manifest and inventory hashes, payload file lengths and hashes, output SHA-256, x64 architecture, unsigned status, and the SHA-256 limitation: it detects byte changes only when the expected digest comes through a trusted release channel and does not authenticate the publisher. It omits build timestamps, normalizes the generated launcher timestamp, and uses fixed cabinet file timestamps.

Windows Server 2025 is listed here only as a build host for the standard GitHub Actions windows-2025 runner. It remains outside the App Installer runtime support matrix in compatibility.json. The build still stops if the pinned PowerShell, .NET, Roslyn, IExpress, MakeCab, or Expand observations differ.

### Legacy executable inventory

Both legacy executable files have been removed from the repository. Their historical hashes, commit IDs, and provenance limits remain in `tools/installer-exe-build.json`; neither path is eligible as current build output or a release asset.

| Removed path | Historical repository evidence | Status |
| --- | --- | --- |
| `builds/install-GUI.exe` | Added in Git commit `81952a64201bbadf4418922953890497157db669`, last changed in `96b07b97894988a00660d967c53d4623a3e83115`. File version `2.0.6.0`, product `myTech.Today App Installer`, SHA-256 `D24CAF70EB50CAD3F54F5CF11F8FF2D961D8090F929B0AB820CD2F9D9376AA86`. | Removed. The old IExpress seed's original source and any historical distribution path remain unknown. Current builds generate a launcher from the pinned Microsoft IExpress tool. |
| `builds/new/install-gui.exe` | Added in Git commit `737cb1c01964a0743c4eb815e46fcfde4a3e15a8`. File version resources said `11.00.26100.1 (WinBuild.160101.0800)`, product `Internet Explorer`, company `Microsoft Corporation`, SHA-256 `C4020D50334AA923226A0655E5797EF329C1C8B7C69B263125B94840610E50AC`. | Removed as an unrelated executable with unknown origin, contents, runtime requirements, and external distribution status. |

The previous files are not part of current builds. The retained metadata documents their repository history and does not establish whether either was distributed externally.

The supported release package is the versioned artifact generated by `tools/Build-InstallerExe.ps1` and selected with its adjacent `.build.json` provenance. Its release assets include the `.sha256` sidecar and `.release.json` manifest. It is an unsigned IExpress launcher, not a standalone PowerShell runtime. It targets the exact Windows 10 release/build pairs from version 1809 through 22H2 and the listed Windows 11 Home or Pro x64 releases, with a compatible installed engine. The GUI requires Windows PowerShell 5.1 with .NET Framework 4.7.2 or PowerShell Core 7.2.0 through 7.6.9 with Windows Desktop runtime 10. A local generated file is build output, not evidence that a GitHub release was published.

### GitHub Actions build and compatibility checks

The workflow at .github/workflows/windows-build-compatibility.yml runs on pull requests targeting main and pushes to main using the standard x64 windows-2025 runner. Its two-engine matrix checks Windows PowerShell Desktop 5.1 and PowerShell Core 7.6.9, builds the unsigned versioned EXE from a clean checkout, and runs every test with an `included` disposition in [`tests/ci-regression-inventory.json`](tests/ci-regression-inventory.json). A missing or unexpected PowerShell version fails its matrix leg. The inventory documents platform/runtime prerequisites, fake or read-only boundaries, and an explicit per-engine `included`, `skipped`, or `unavailable` status for every standalone script.

Run the same offline regression suite locally on Windows with PowerShell Core 7.6.9:

```powershell
pwsh -NoProfile -File .\tests\Invoke-CIRegressionSuite.ps1 -Engine Core-7.6.9
```

Run the focused profile privacy regression under both supported Windows engines:

```powershell
powershell.exe -NoProfile -File .\tests\test-profile-export-privacy.ps1
pwsh -NoProfile -File .\tests\test-profile-export-privacy.ps1
```

The inventory currently contains 40 standalone `test-*.ps1` scripts. Its matrix counts are Desktop-5.1: 34 included, 4 skipped, 2 unavailable; Core-7.6.9: 37 included, 1 skipped, 2 unavailable. `test-profile-export-privacy.ps1` checks identity-free default exports, the disclosed CLI opt-in, and legacy profile imports using temporary files. The separate syntax check also runs in each leg. `test-compatibility-runtime-current-host.ps1` and `test-startup-entrypoints-offline.ps1` are explicitly unavailable on the Windows Server 2025 runner, with reasons in the inventory. Each Windows job writes a summary that separates the Server build result, its pinned engine and offline regression evidence, and supported Windows client GUI capability/startup as `NOT RUN`. Versioned release publication also requires a revision-bound manual record for both client engines and a complete, current remote protection record with durable evidence; both are validated separately from the Server runner. The Core leg passes its validated, locally built executable to the release-asset simulation; CI fails if that expected artifact is missing. Without a built artifact, a local run reports that simulation as unavailable.

As of November 4, 2026, GitHub's published hosted-image list has Windows Server x64 images and Windows 11 Arm64 images, but no Windows 11 x64 client image matching this support matrix. Recheck the [GitHub-hosted runner image list](https://github.com/actions/runner-images#available-images) before relying on hosted labels. Until a supported x64 client runner is available, use the [Windows client GUI release checklist](WINDOWS_CLIENT_GUI_RELEASE_CHECKLIST.md) on an already-provisioned Windows 11 25H2 or 26H2 Home/Pro x64 host. Record both engine results in [WINDOWS_CLIENT_GUI_RELEASE_EVIDENCE.json](WINDOWS_CLIENT_GUI_RELEASE_EVIDENCE.json), tied to the exact release source revision, before tagging. The release workflow checks this record and leaves client capability/startup as `NOT RUN` when evidence is absent. A Windows Server or wrong-engine result cannot satisfy client validation.

The workflow also runs `native-cli-linux` on `ubuntu-24.04` and `native-cli-macos` on `macos-15`. They check native syntax and the compatibility contract, run platform-selection and argument-capture tests through temporary fake package-manager commands, exercise the CLI `-WhatIf` boundary, and run `install.sh` from a temporary path with spaces through a fake `pwsh` command. No PowerShell setup action or package-manager installation command is used. The jobs record the runner's preinstalled PowerShell version and still run the isolated checks when that version differs from the contract. As of November 1, 2026, the published [Windows Server 2025](https://github.com/actions/runner-images/blob/main/images/windows/Windows2025-Readme.md) image lists PowerShell 7.6.7 and [macOS 15](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md) lists 7.6.4, while `compatibility.json` pins 7.6.9. The Windows Core matrix and release packaging require exact 7.6.9 and reject a mismatch without provisioning another runtime, so those hosted legs remain unavailable until their image provides the pinned engine. The published [Ubuntu 24.04](https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md) image lists PowerShell 7.6.9. The `Required shared CLI compatibility` job requires both native jobs, the Windows matrix, and exact 7.6.9 on both native runners; a version mismatch is reported as unavailable and fails that required status. It also gates the reusable workflow used by release validation. Configure this job as a required branch-protection check for shared CLI changes; remote branch-protection settings were not inspected or changed here.

The previous runner omitted the following 12 existing scripts. The table records their prerequisites, boundaries, and matrix dispositions; the JSON inventory remains the source of truth for all 40 scripts, including tests already present in the runner and the new inventory-contract and compatibility-review tests.

| Previously omitted test | Platform prerequisites | Boundary | Desktop 5.1 | Core 7.6.9 |
| --- | --- | --- | --- | --- |
| `test-belarc-installer-trust.ps1` | Windows, PowerShell 5.1+, writable temp directory | Synthetic payload bytes; fake download, signature, and process callbacks; ACL write stubbed | Included | Included |
| `test-cli-runtime-handoff.ps1` | Windows process/path behavior, PowerShell 5.1+ | Fake WinGet, temporary profiles, and WhatIf | Included | Included |
| `test-compatibility-runtime-current-host.ps1` | Supported Windows 11 client build, edition, x64, and GUI runtime | Read-only host/runtime inspection | Unavailable: CI host is Windows Server 2025 | Unavailable: CI host is Windows Server 2025 |
| `test-custom-app-script-results.ps1` | Windows, PowerShell 5.1+, writable temp directory | Fake native commands and Start-Process; no package manager or browser launch | Included | Included |
| `test-executable-install-lifecycle.ps1` | Windows, PowerShell 5.1+, writable temp directory | Generated temporary payloads; reads ACLs but does not alter OS install state | Included | Included |
| `test-gui-queue-state.ps1` | Windows, PowerShell 5.1+, writable temp directory | Isolated queue files and stubbed UI/process behavior | Included | Included |
| `test-gui-startup-capability.ps1` | PowerShell 5.1+ | Synthetic host/engine data and injected Forms loader/CLI runner | Included | Included |
| `test-install-bat-elevation.ps1` | Windows, cmd.exe, pwsh.exe, .NET Framework C# compiler | Fake launchers and Start-Process with temporary batch fixtures; no elevation or WinGet | Included | Included |
| `test-installer-release-assets.ps1` | Windows, Core 7.6.9, executable and adjacent manifest from CI build | Temporary asset staging and fake source/API; no network, upload, signing, or publication | Skipped: Core build input required | Included after validated build |
| `test-package-dependency-outcomes.ps1` | Windows, System.Drawing, PowerShell 5.1+, writable temp files | Injected fake package commands; no live WinGet | Included | Included |
| `test-remote-helper-trust.ps1` | Windows, PowerShell 5.1+, writable temp directory | Fake transport, signature, and process callbacks; no helper download or launch | Included | Included |
| `test-winget-bootstrap.ps1` | Windows, PowerShell 5.1+, writable temp directory and local package fixtures | Synthetic packages and fake download/install callbacks; no release request, package download, or Add-AppxPackage call | Included | Included |

`test-update-scan-status.ps1` was already in the previous runner and remains included on both engines. Its package-command boundary is stubbed. The added inventory-contract test verifies that every standalone script has exactly one inventory entry, that counts match, and that the separate injected-failure test propagates a nonzero child exit code. A script-level platform skip exits with code 77 and is reported separately from passed tests. The safety harnesses use fake package-manager and scheduler commands and temporary file and profile roots; they do not invoke live package providers, network downloads, elevation, or real scheduled tasks. Passing source checks do not verify live provider or Task Scheduler behavior, code signing, hosted workflow execution, or remote branch and tag protection settings.

The repository is public, so standard GitHub-hosted runners are free. The job also skips if the repository is private. Artifact upload is available only from a manual run and defaults off. It includes the versioned unsigned EXE and adjacent .build.json provenance file for three days. GitHub Free includes 500 MB of artifact and package storage combined; current storage use is not available to this workflow, so upload only when the owner has sufficient included storage.

### Versioned unsigned GitHub releases

**Release version mapping:** GUI 2.0.6 / CLI 2.0.2

VERSION is the canonical current version source. Its GUI entry defines the executable product version, stable release tag, four-part Windows file version, and versioned artifact name. The CLI entry remains independently versioned. Both script headers and startup banners show their respective script versions, and the release manifest records both values. Prerelease and build-metadata versions are not supported by the current release workflow.

`.github/workflows/versioned-unsigned-release.yml` runs only for pushed tags beginning with `v`. The validator accepts only exact stable `vMAJOR.MINOR.PATCH` tags and requires the version to equal the GUI version in `VERSION`; the GUI and CLI script versions must both match their entries in that file. The release is one unsigned x64 GUI package named `AppInstaller-<GUI-version>-win-x64.exe`. The pipeline publishes its `.exe.sha256` sidecar, adjacent `.exe.build.json` builder provenance, and `AppInstaller-<GUI-version>-win-x64.release.json` release manifest. The release notes are published in the GitHub release body.

The tag must be protected by a GitHub ruleset or tag protection rule, point to a commit on the repository default branch, and still resolve to the commit that triggered the workflow. The workflow requires the tagged commit's workflow files to match the current default branch because `GITHUB_TOKEN` cannot be granted workflow-write permission. Configure and review tag protection before the first release. Track that external review in the [release protection verification record](RELEASE_PROTECTION_VERIFICATION.md); the local workflow check cannot prove the remote ruleset, and its current status is **NOT VERIFIED**. The release caller reuses the two-engine compatibility workflow, then rebuilds with the same pinned builder after both jobs pass. It does not store an intermediate Actions artifact.

The validation and test jobs have `contents: read`; only the final publishing job has `contents: write`. It uses the automatically provided `github.token`, creates a draft, uploads the exact asset allowlist, and publishes the draft only after every upload succeeds. It never creates or pushes tags, signs the EXE, or overwrites an existing release. A failed upload can leave an unpublished draft that must be removed or repaired before retrying the same tag.

The release manifest records the GUI and CLI versions, source tag and commit, build toolchain, compatibility contract and digest, full payload inventory, x64 target, and successful Windows PowerShell 5.1 and PowerShell Core 7.6.9 jobs. Release notes list the supported Windows and PowerShell matrix, prerequisites, GUI and CLI commands, known limits, and recovery steps. The EXE does not bundle PowerShell.

The repository is public and the workflow uses the standard x64 `windows-2025` runner, so GitHub documents standard hosted runner minutes as free for public repositories. This release workflow does not store Actions artifacts; public GitHub release assets have no total size or bandwidth quota, subject to GitHub's per-file asset limit. The separate manual CI artifact upload remains subject to the account's Actions storage quota. See [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions), [GitHub-hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners), and [GitHub release asset quotas](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases#storage-and-bandwidth-quotas).

The `.sha256` file provides the executable digest for comparison. SHA-256 detects byte changes only when the expected digest is obtained through a trusted release channel. It does not authenticate the publisher or replace a digital signature. The EXE is intentionally unsigned; Windows SmartScreen or security software may warn. Do not disable security controls to run it. If the digest differs, discard the file and download it again from the trusted release page.

`tests/test-executable-build.ps1` builds twice from isolated clean source copies and compares the executable SHA-256 values. The resulting package remains unsigned and does not bundle PowerShell, so it requires a compatible installed PowerShell runtime at launch. It follows the current `compatibility.json` contract and is not a standalone executable.

`payload-manifest.json` is the runtime payload allowlist. It names both entry points, launchers, shared modules, the application catalog, all app scripts, and the shipped default profiles. The profile filenames are enumerated so user-exported profiles are not bundled. The builder excludes development directories, tests, fixtures, logs, temporary files, local secrets, and unrelated binaries.

The builder creates `payload-integrity.json` inside the cabinet. It records the GUI and CLI versions, manifest hash, and SHA-256 plus byte length for every listed runtime file. Startup validates this metadata and the full catalog before loading the GUI or CLI. Missing or invalid payload files stop startup; the CLI does not substitute its old shortened catalog. These hashes detect incomplete or damaged packages and do not authenticate the unsigned executable.

Runtime resources resolve from the directory containing the running entry script. The Windows bootstrap resolves `install.bat` and `tools/Start-Installer.ps1` from the extracted executable payload. The EXE is an unsigned IExpress launcher, not a machine installer. GUI startup validates and installs the payload in the current user's `%USERPROFILE%\myTech.Today\AppInstaller` directory. The CLI uses the corresponding per-user application-data paths on macOS and Linux. No runtime resource is resolved from the caller's current directory.

### Windows executable install lifecycle

The Windows install is per-user and inherits ACLs from the user's profile. It does not request elevation or create a product Start Menu shortcut. A machine-wide install is not supported. PowerShell and .NET runtimes are managed by the existing prerequisite flow and are never removed by App Installer uninstall.

The stable user path contains one active version. A previous script install is adopted when its product payload markers can be validated. The GUI repairs or upgrades from the validated launch payload. It stages a complete tree in a sibling directory, verifies payload hashes, and switches directories on the same volume. The previous tree stays available until the activated payload passes integrity validation. If activation fails, the failed tree is moved to a `.AppInstaller.failed-*` recovery path and the previous tree is restored. If cleanup of the old tree fails after a successful activation, the exact backup path and error are reported and the backup is retained.

`.app-installer-install.json` records the installed version, current-user scope, and each owned payload file with its length and SHA-256. The installer carries forward unowned files and directories, queue state and its recovery backup, user profiles, and app configuration. An unowned file that conflicts with a packaged path stops the operation without replacing it. Edited profile files stay at their original paths and are included in the next payload integrity record. Edited owned code is copied to `.app-installer-preserved` before repair and the original and recovery paths are reported. A root, directory, or file with a custom ACL that differs from the inherited profile ACL stops staging instead of changing permissions.

Logs stay under `%USERPROFILE%\myTech.Today\logs`. The executable itself stays where it was downloaded or copied. This lifecycle does not create or remove product shortcuts. Existing user-created shortcuts and shortcuts created for other applications are outside the install root and are left alone. When removing the application, queue data, profiles, logs, app configuration, unowned files, edited owned files, and downloaded runtimes are retained.

The management entry point supports explicit lifecycle actions from a validated payload directory. Install, upgrade, and repair use `-SourceRoot` for that payload and `-InstallRoot` for a disposable or user-owned destination. Uninstall first reports the owned file count without deleting anything. To remove unchanged owned program files while retaining user data, pass both `-KeepData` and `-RemoveOwnedFiles`:

```powershell
pwsh -NoProfile -File .\tools\Manage-AppInstallerInstall.ps1 -Action Install -SourceRoot . -InstallRoot "$env:USERPROFILE\myTech.Today\AppInstaller" -WhatIf
pwsh -NoProfile -File .\tools\Manage-AppInstallerInstall.ps1 -Action Repair -SourceRoot . -InstallRoot "$env:USERPROFILE\myTech.Today\AppInstaller" -WhatIf
pwsh -NoProfile -File "$env:USERPROFILE\myTech.Today\AppInstaller\tools\Manage-AppInstallerInstall.ps1" -Action Uninstall -KeepData
pwsh -NoProfile -File "$env:USERPROFILE\myTech.Today\AppInstaller\tools\Manage-AppInstallerInstall.ps1" -Action Uninstall -KeepData -RemoveOwnedFiles -WhatIf
```

RemoveOwnedFiles deletes only manifest-owned files whose current length and SHA-256 still match. Modified owned files are retained. The root directory remains if user data or unowned files remain. KeepData is required because this lifecycle does not offer an option to delete profiles, queue state, logs, or other user data.

If a legacy script install has neither a valid ownership manifest nor valid payload-integrity metadata, uninstall stops before removing files. Upgrade or repair it from a verified payload first so the installer can record a trustworthy local file baseline.

Run the offline lifecycle and payload checks with:

```powershell
pwsh -NoProfile -File .\tests\test-executable-install-lifecycle.ps1
pwsh -NoProfile -File .\tests\test-executable-payload.ps1
```

The current versioned package is unsigned; version-resource metadata is not a code signature. `tests/test-executable-build.ps1` checks the generated artifact and provenance without launching the executable. `tests/test-executable-resource-update.ps1` exercises cabinet-resource replacement on a temporary copy of the current versioned executable, building that executable in a temporary directory when needed.

## Administrator & Antivirus Notes

- Runtime discovery and the setup launcher run in the current user session and do not request elevation. Individual package installers may request administrator approval when their operation requires it.
- `invoke-elevated-install.ps1` is an explicit wrapper for a batch or executable target. It requests UAC elevation, waits for the child, and returns its confirmed exit code. Pass the target path first, followed by its arguments. A canceled UAC prompt returns a nonzero result. The wrapper does not change execution policy.
- **Antivirus / SmartScreen behavior:**
  - The current versioned release EXE is an unsigned IExpress package. Windows SmartScreen or security software may warn about it.
  - If a security product flags or quarantines a package, stop and verify its source and any published signature or digest. If you cannot verify it, or an organization policy blocks it, contact your administrator rather than overriding the warning.

## Windows launch and PowerShell execution policy

`install.bat` starts the GUI by default. Add `-ForceCLI` to select the CLI entry script directly. The shared resolver chooses a compatible installed engine before the app starts. It prefers PowerShell Core 7.2.0 through 7.6.9 for CLI and for GUI when the required Desktop runtime and assemblies load; Windows PowerShell 5.1 supports both entry points. A missing `pwsh.exe` does not by itself trigger runtime installation when Windows PowerShell 5.1 can run the selected entry point. If no installed candidate can run the CLI, the pinned PowerShell Core 7.6.9 provisioning plan is offered only through the existing consent flow.

Launch the source scripts with a supported host and its normal execution policy:

```powershell
.\install.bat
.\install.bat -ForceCLI -Action Status
powershell.exe -NoProfile -File .\app-installer.ps1
powershell.exe -NoProfile -File .\app-installer-cli.ps1 -Action Status
pwsh -NoProfile -File .\app-installer.ps1
pwsh -NoProfile -File .\app-installer-cli.ps1 -Action Status
```

For automation, use the CLI script directly and include `-WhatIf` when reviewing a state-changing action. `-Action Status` is read-only. To request an elevated batch or EXE operation explicitly, call the helper with the target path followed by the target's arguments:

```powershell
pwsh -NoProfile -File .\app-installer-cli.ps1 -Action InstallMissing -WhatIf
powershell.exe -NoProfile -File .\invoke-elevated-install.ps1 .\install.bat -ForceCLI -Action Status
```

When a release is available, obtain the versioned file and matching release metadata from [GitHub Releases](https://github.com/mytech-today-now/app_installer/releases). The two removed legacy executable paths are not current product downloads. The direct PowerShell script and `install.bat` launch paths do not alter policy settings. Check effective scopes with `Get-ExecutionPolicy -List`; this installer does not write them. Execution policy is a PowerShell safety feature, not a code-integrity check. See Microsoft's [execution policy guidance](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies?view=powershell-7.5).

For a signed Windows script, inspect its Authenticode result before launch:

```powershell
Get-AuthenticodeSignature -LiteralPath .\app-installer.ps1 | Format-List Status, SignerCertificate
```

Run a downloaded script only when the signature status is `Valid` and the signer matches the publisher identity published for that release. A valid signature from an unexpected signer is not sufficient. This checkout does not identify a project signing certificate or signer thumbprint, so do not assume source scripts or locally built packages are signed. Microsoft's [PowerShell signing guidance](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_signing?view=powershell-7.5) and [`Get-AuthenticodeSignature` reference](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/get-authenticodesignature) explain signature verification.

Do not use `Unblock-File` or a policy change as a substitute for checking a signature or independently verifying a digest.

## McAfee removal helper

McAfee Uninstaller is blocked in this checkout. Its catalog entry returns a failed custom-script result before downloading MCPR or checking/removing installed products because no independently reviewed digest or Authenticode signer pin is configured. When a pin is approved, the shared verifier stages MCPR in a unique protected temporary directory, checks every configured identity, reports the child exit code, and removes only its owned staging files. No live MCPR download or execution is part of offline validation.

## Optional remote hosts and restore-point helpers

The Hosts File Manager and Manage Restore Points helpers remain unavailable in this checkout because their reviewed immutable source URLs and independent SHA-256 pins are not configured. Selecting either app fails closed before a request, persistent setup, shortcut creation, or helper execution. No live helper source was queried for this decision. Do not launch either helper from a mutable branch URL.

When a reviewed release is configured, the installer verifies the exact downloaded bytes before launch. The installed shortcut targets the local wrapper, which repeats verification each time it runs. Use the direct commands printed by the installer, which follow this form and preserve the current PowerShell policy:

```powershell
powershell.exe -NoProfile -File "$env:USERPROFILE\myTech.Today\scripts\hosts.ps1" -Force
powershell.exe -NoProfile -File "C:\myTech.Today\ManageRestorePoints\Manage-RestorePoints.ps1" -Action List
powershell.exe -NoProfile -File "C:\myTech.Today\ManageRestorePoints\Manage-RestorePoints.ps1" -Action Configure
powershell.exe -NoProfile -File "C:\myTech.Today\ManageRestorePoints\Manage-RestorePoints.ps1" -Action Create -Description 'My Backup'
powershell.exe -NoProfile -File "C:\myTech.Today\ManageRestorePoints\Manage-RestorePoints.ps1" -Action Monitor
```

If source verification fails, inspect the reported status before trying again. A nonzero or unknown helper result does not confirm that hosts or restore-point state changed.

If a launcher or verified child runner detects that PowerShell policy prevented the script from starting, it reports:

> PowerShell policy prevented this script from starting. No policy setting was changed. Use the signed release or contact your administrator.

See the [PowerShell signing guidance](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_signing?view=powershell-7.5) for signature verification. Do not change user, machine, or organization policy to work around a blocked launch.

## Installation

### Windows Installation

1. **Clone or download** the repository:
   ```powershell
   git clone https://github.com/mytech-today-now/PowerShellScripts.git
   cd PowerShellScripts\app_installer
   ```

2. **Start the validated launcher:**
   - The launcher checks Windows 10 version 1809 or later, or a listed Windows 11 release, before package-manager calls.
   - It probes all discovered PowerShell candidates using the rules in `compatibility.json` before considering runtime provisioning.
   - If no installed engine can run the CLI, it presents a pinned, current-user PowerShell Core 7.6.9 plan and asks for explicit consent. If no PowerShell engine can start the preflight, install.bat prints the manual recovery source and pin without downloading or installing anything.

3. **Run as Administrator**:

   **GUI Version (Windows Only - Recommended):**
   ```powershell
   .\app-installer.ps1
   ```

   **Command-Line Version:**
   ```powershell
   .\app-installer-cli.ps1
   ```

### macOS Installation

1. **Install PowerShell 7.6.9**:
   ```bash
   brew install --cask powershell
   ```

2. **Install Homebrew** (if not already installed):
   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```

3. **Clone the repository**:
   ```bash
   git clone https://github.com/mytech-today-now/PowerShellScripts.git
   cd PowerShellScripts/app_installer
   ```

4. **Run the CLI installer**:
   ```bash
   pwsh ./app-installer-cli.ps1
   ```

### Linux Installation

1. **Install PowerShell 7.6.9**:
   - **Ubuntu/Debian:**
     ```bash
     wget https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb
     sudo dpkg -i packages-microsoft-prod.deb
     sudo apt-get update
     sudo apt-get install -y powershell
     ```
   - **Fedora:**
     ```bash
     sudo dnf install powershell
     ```
   - **Arch Linux:**
     ```bash
     yay -S powershell-bin
     ```

2. **Clone the repository**:
   ```bash
   git clone https://github.com/mytech-today-now/PowerShellScripts.git
   cd PowerShellScripts/app_installer
   ```

3. **Run the CLI installer**:
   ```bash
   pwsh ./app-installer-cli.ps1
   ```

## Usage

### GUI Mode (app-installer.ps1) - Recommended

Launch the graphical interface:

```powershell
.\app-installer.ps1
```

**GUI Features:**
- **Search & Filter** - Real-time search box to filter applications by name, category, or description
  - Type to instantly filter the list (e.g., "chrome", "browser", "video")
  - Clear button (X) to reset search
  - Result count shows "Showing X of 271 applications"
  - Checkbox states preserved when filtering
- **Application Table** - Browse all 271 applications with checkboxes
- **Category Grouping** - Applications organized by category
- **Status Column** - Shows "Installed" with version or "Not Installed"
- **Progress Tracking** - Real-time progress: "0 / 5 applications" updates as you select
- **Buttons:**
  - **Refresh Status** - Re-scan for installed applications
  - **Select All** - Select all applications (filtered or all)
  - **Select Missing** - Select only applications not currently installed
  - **Deselect All** - Clear all selections
  - **Export Selection** - Save selected applications to a JSON profile
  - **Import Selection** - Load applications from a JSON profile
  - **Install Selected** - Install checked applications
  - **Uninstall Selected** - Remove checked applications (only installed apps)
  - **Exit** - Close the application

**Progress Display:**
- When you select apps: Shows "0 / X applications" (X = number selected)
- During installation: Shows "Y / X applications" (Y = completed, X = total)
- Progress bar fills as each application installs

### Command-Line Mode (app-installer-cli.ps1)

**Interactive Menu:**
```powershell
.\app-installer-cli.ps1
```

**Menu Options:**
- **1-212:** Install individual application by number
- **A:** Install all applications
- **M:** Install missing applications only
- **U:** Check for updates
- **E:** Export selection to profile
- **I:** Import selection from profile
- **X:** Uninstall/Remove selected applications
- **S/R:** Show/Refresh status
- **Q:** Quit

**Command-Line Parameters:**

**Install all applications:**
```powershell
.\app-installer-cli.ps1 -Action InstallAll
```

**Install only missing applications:**
```powershell
.\app-installer-cli.ps1 -Action InstallMissing
```

**Show status only:**
```powershell
.\app-installer-cli.ps1 -Action Status
```

**Install specific application:**
```powershell
.\app-installer-cli.ps1 -AppName "Chrome"
```

## Export/Import Configuration Profiles

Both the GUI and CLI versions support exporting and importing application selection profiles. This feature is useful for:
- **Backing up your application selections**
- **Deploying the same set of applications to multiple machines**
- **Sharing configurations with team members**
- **Standardizing installations across an organization**

### Profile Format

Profiles are saved as JSON files with the following structure:

```json
{
  "Version": "1.0",
  "Timestamp": "2025-11-10T18:40:47",
  "InstallerVersion": "1.3.8",
  "Applications": [
    "Google Chrome",
    "7-Zip",
    "VLC Media Player",
    "Visual Studio Code",
    "Git"
  ]
}
```

### Default Profile Location

Profiles are saved to: `%USERPROFILE%\mytech.today\app_installer\profiles\`

Default filename format: `profile-{yyyy-MM-dd-HHmmss}.json`

New profiles omit the computer name and user name so application selections can be shared without local identity details. Older profiles that contain `ComputerName` or `UserName` remain importable; imports ignore those fields and do not change the source file. Import logs normalize line breaks and Markdown table separators, bound untrusted metadata, and omit legacy device and account identifiers. The CLI offers a separate diagnostic identity prompt during export. It explains that the identifiers may disclose the device and account if the profile is shared, and includes them only when you type `YES`. The GUI export does not include identity fields.

### Using Export/Import in GUI

1. **Export Selection:**
   - Select the applications you want to export
   - Click the **"Export Selection"** button
   - Choose a location and filename (or use the default)
   - The profile will be saved with its timestamp, installer version, and selected application names

2. **Import Selection:**
   - Click the **"Import Selection"** button
   - Browse to and select a profile JSON file
   - Review the confirmation dialog showing the number of applications
   - Click "Yes" to select the applications from the profile
   - Applications not available in the current installer version will be listed as warnings

### Using Export/Import in CLI

1. **Export Selection:**
   - From the main menu, press **E**
   - Enter the application numbers to export (e.g., "1,3,5" or "1-10")
   - Enter a filename or press Enter to use the default
   - The profile will be saved to the profiles directory

2. **Import Selection:**
   - From the main menu, press **I**
   - Select a profile from the list or enter a full path
   - Review the profile information and confirm installation
   - Applications will be installed automatically if confirmed

### Handling Missing Applications

When importing a profile, the installer will:
- ✅ Identify which applications from the profile are available in the current installer
- ⚠️ Warn about applications that are not available (e.g., removed or renamed apps)
- ✅ Proceed with installing only the available applications
- 📝 Log all import operations including missing applications

## Directory Structure

```
app_installer/
├── app-installer.ps1                # GUI-based installer (recommended)
├── app-installer-cli.ps1            # Command-line menu-driven installer
├── apps/                            # Individual app installation scripts (212 total)
│   ├── chrome.ps1                   # (Uses winget)
│   ├── brave.ps1                    # (Uses winget)
│   ├── firefox.ps1                  # (Uses winget)
│   ├── vscode.ps1                   # (Uses winget)
│   ├── python.ps1                   # (Uses winget)
│   ├── docker.ps1                   # (Uses winget)
│   ├── obs.ps1                      # (Uses winget)
│   ├── belarc.ps1                   # Custom installer
│   ├── shutup10.ps1                 # Custom installer
│   ├── filemail.ps1                 # Custom installer
│   ├── grok-shortcuts.ps1           # Creates shortcuts
│   ├── chatgpt-shortcuts.ps1        # Creates shortcuts
│   ├── dictation-shortcut.ps1       # Creates shortcuts
│   ├── uninstall-mcafee.ps1         # McAfee removal tool
│   └── ... (89 more scripts)
├── README.md                        # This file
├── CHANGELOG.md                     # Version history
```

## Uninstall Applications

Both the GUI and CLI versions support uninstalling applications that were previously installed via winget.

### GUI Uninstall (app-installer.ps1)

1. **Select Applications** - Check the applications you want to uninstall
2. **Click "Uninstall Selected"** - Dark red button next to "Install Selected"
3. **Confirm Uninstall** - Review the list of applications to be removed
4. **Progress Tracking** - Watch real-time progress as apps are uninstalled
5. **Completion** - View success/fail statistics

**Safety Features:**
- ⚠️ **Confirmation required** - Cannot uninstall without explicit confirmation
- ⚠️ **Only installed apps** - Only shows applications that are currently installed
- ⚠️ **Cannot undo** - Uninstall is permanent (warning shown in confirmation)
- ✅ **Detailed logging** - All uninstall operations logged to centralized log
- ✅ **Error handling** - Failed uninstalls are reported with error details

### CLI Uninstall (app-installer-cli.ps1)

1. **Select Menu Option "X"** - Choose "X. Uninstall/Remove Selected Applications"
2. **Enter Application Numbers** - Type numbers (e.g., "1,3,5" or "1-10")
3. **Confirm Uninstall** - Review the list and confirm with "Y"
4. **Progress Tracking** - Watch progress with success/fail counts
5. **Completion** - View final statistics

**Example:**
```powershell
.\app-installer-cli.ps1
# Select "X" from menu
# Enter: 1,5,10
# Confirm: Y
```

**Important Notes:**
- ⚠️ Applications without a WingetId cannot be uninstalled via this tool
- ⚠️ Some applications may require manual uninstallation from Windows Settings
- ⚠️ Uninstalling critical system applications may cause issues
- ✅ The application list automatically refreshes after uninstall completes

## Logging

All activities are logged to:
```
%USERPROFILE%\mytech.today\logs\install-yyyy-MM.md
```

**Log Format:** Markdown table with icons
**Log Rotation:** Monthly (one file per month)
**Log Levels:** ℹ️ INFO, ⚠️ WARNING, ❌ ERROR, ✅ SUCCESS

**Example Log Entry:**
```markdown
| 2025-11-02 10:30:00 | ✅ **SUCCESS** | Google Chrome installed successfully |
```

## How It Works

### Application Registry

Both scripts maintain an internal registry of all 212 supported applications with:
- **Name:** Display name
- **ScriptName:** Individual installation script filename
- **WingetId:** Windows Package Manager ID (if available)
- **Category:** Application category for organization

### Installation Process

1. **Detection:** Checks if application is already installed via winget or registry
2. **Method Selection:**
   - If custom script exists in `apps/` folder → Use custom script
   - If WingetId is defined → Use `winget install`
   - Otherwise → Display warning
3. **Execution:** Run installation with silent/automated parameters
4. **Logging:** Log all activities to centralized log file
5. **Status:** Display confirmed success, failure, or unknown results with color-coded output

Custom app scripts run in an isolated PowerShell process. If the installer cannot confirm a script's result, it reports the result as unknown and does not mark the app installed. Check the app's current state before retrying.

### Version Detection

- **Primary:** Uses `winget list` for fast, accurate detection
- **Fallback:** Checks Windows registry for installed programs
- **Display:** Shows version number or "Installed" if version unavailable





## Customization

### Adding New Applications

1. **Add to Application Registry** in `apps-manifest.json`:
   ```powershell
   [PSCustomObject]@{
       Name = "MyApp"
       ScriptName = "myapp.ps1"
       WingetId = "Publisher.MyApp"
       Category = "Utilities"
   }
   ```

2. **Create Custom Script** (optional) in `apps/myapp.ps1`:
   ```powershell
   # Custom installation logic
   Write-Host "Installing MyApp..." -ForegroundColor Cyan
   # Let WinGet show any required terms and collect an explicit decision.
   winget install --id Publisher.MyApp
   ```

3. **Test Installation**:
   ```powershell
   .\app-installer.ps1
   ```

### Modifying Categories

Edit the `Category` property in the application registry to organize apps differently. Available categories:
- Browsers, Development, Productivity, Media, Utilities, Security
- Communication, 3D & CAD, Networking, Writing, Shortcuts, Runtime, Maintenance

## Troubleshooting

### winget Not Available

**Error:** "winget is not available on this system"

**Solutions:**
- Install "App Installer" from Microsoft Store
- Update Windows to latest version
- Verify: `winget --version`
- Restart PowerShell after installation

### Installation Fails

**Error:** "Installation failed. Check log for details."

**Solutions:**
1. Check log file: `C:\mytech.today\logs\install-yyyy-MM.md`
2. Verify internet connection
3. Run as Administrator
4. Try manual installation of specific app
5. Check if antivirus is blocking installation
6. Ensure winget is up to date: `winget upgrade --id Microsoft.Winget.Source`

### Application Not Detected

**Issue:** Installed app shows as "Not Installed"

**Causes:**
- App installed via portable version
- App installed in non-standard location
- Registry entry doesn't match detection pattern
- winget database not updated

**Solutions:**
- Click "Refresh Status" button in GUI
- Restart the application
- Detection is informational only; app will still function

### GUI Not Displaying Correctly

**Issue:** Text too small, buttons clipped, or layout issues

**Solutions:**
- Ensure .NET Framework 4.7.2 or later is installed
  - The GUI installer will automatically detect and offer to install .NET Framework 4.8 if needed
  - If automatic installation fails, download manually from: https://dotnet.microsoft.com/download/dotnet-framework/net48
- Check Windows display scaling settings
- Try running on different monitor if using multi-monitor setup
- GUI automatically adapts to DPI scaling

### .NET Framework Installation Issues

**Issue:** GUI fails to start with assembly loading errors

**Solutions:**
- Run `app-installer.ps1` - it will automatically detect missing .NET Framework
- If prompted, allow the script to install .NET Framework 4.8
- A system restart may be required after .NET Framework installation
- If automatic installation fails, install manually from Microsoft's website
- Verify installation by running `app_installer\test-dotnet-check.ps1`

## Best Practices

✅ **Run as Administrator** - Required for most installations
✅ **Check winget availability** - Ensures smooth installation
✅ **Review logs** - Check `C:\mytech.today\logs\` for details
✅ **Install missing only** - Saves time on already-configured systems
✅ **Restart after major installs** - Some apps (Docker, Python) require restart
✅ **Use GUI version** - More user-friendly and provides better feedback
✅ **Select apps carefully** - Don't install everything if you don't need it

## Security Considerations

- All downloads use HTTPS
- winget packages are verified by Microsoft
- Custom scripts download from official sources only
- McAfee removal remains blocked until an independently reviewed MCPR SHA-256 digest or Authenticode signer thumbprint is configured.
- Belarc Advisor and O&O ShutUp10 are currently unavailable until their immutable source, SHA-256 digest, and Authenticode signer thumbprint are independently reviewed and configured. Neither helper is downloaded or run while those pins are unset.
- The CLI omits unavailable actions from its numbered menu and blocks direct install requests; the GUI marks them unavailable and blocks selection. Verified helper transfers reject redirects and changed response sources before execution.
- No credentials or sensitive data stored
- All installations run with user consent
- Logs contain no sensitive information

## Recent Updates

### v2.0.6 (GUI) / v2.0.2 (CLI) - 2026-03-17
- ✅ **Access Denied Fix** - All `Test-Path` calls wrapped in `Safe-TestPath` helper with try/catch and `-ErrorAction SilentlyContinue` to suppress `UnauthorizedAccessException` on protected paths
- ✅ **Security Warning Fix** - `Unblock-File` called after every `Copy-Item` during self-installation so scripts copied to the system location are automatically unblocked (removes Zone.Identifier ADS)
- ✅ **Feature Parity** - Both GUI and CLI scripts share the same `Safe-TestPath` helper and `Unblock-File` integration

### v2.0.5 (GUI) / v2.1.0 (Platform-Detect) - 2026-03-14
- ✅ **Chrome Install Fix (historical)** - A previous adapter passed `--force` for Chrome; the current shared adapter omits it and uses WinGet's normal install behavior.
- ✅ **Exit Code Preservation** - `platform-detect.ps1` returns actual exit codes instead of hardcoded `1`
- ✅ **Smart Success Detection** - Output pattern matching for "already installed" / "Successfully installed"
- ✅ **WinGet Already-Installed Handling** - GUI accepts `-1978335191` as success from custom scripts

### v2.0.4 (GUI) - 2026-03-13
- ✅ **Self-Healing Dependencies** - Auto-downloads missing `platform-detect.ps1` and `apps-manifest.json` from GitHub
- ✅ **System Path Fix** - Resolves failures when running from system install location

### v2.0.3 (GUI) - 2026-03-13
- ✅ **O&O ShutUp10 Fix** - `-NonInteractive` switch prevents GUI queue blocking
- ✅ **Exit Code 30 Accepted** - O&O ShutUp10's exit code 30 treated as success

### v2.0.2 (GUI) - 2026-03-13
- ✅ **Dependency Copy Fix** - Copies `platform-detect.ps1` and `apps-manifest.json` to system install location

### v2.0.0 (GUI & CLI) - 2025-12-16
- ✅ **Major Cross-Platform Release** - Full refactoring for Windows, macOS, and Linux
- ✅ **Shared Core Module** - AppInstallerCore.psm1 eliminates code duplication
- ✅ **Dynamic App Registry** - Loads 271+ apps from apps-manifest.json

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Test Windows 10 x64 from version 1809, Windows 11 25H2 and 26H2 x64, Windows PowerShell 5.1, and PowerShell Core 7.2.0 and 7.6.9
4. Update documentation if adding new features
5. Submit a pull request with detailed description

## Support

For issues, questions, or contributions:
- **GitHub Issues:** https://github.com/mytech-today-now/PowerShellScripts/issues
- **Documentation:** See this README and [CHANGELOG.md](CHANGELOG.md)
- **Company Website:** https://mytech.today

## Version History

See [CHANGELOG.md](CHANGELOG.md) for detailed version history.

**Recent Versions:**
- **v2.0.6 (GUI) / v2.0.2 (CLI)** - Access Denied fix (Safe-TestPath), security warning fix (Unblock-File)
- **v2.0.5 (GUI) / v2.1.0 (Platform-Detect)** - Historical Chrome workaround (the `--force` flag is no longer added), exit code preservation, smart success detection
- **v2.0.4 (GUI)** - Self-healing dependencies at system install path
- **v2.0.3 (GUI)** - O&O ShutUp10 non-interactive fix
- **v2.0.0 (GUI & CLI)** - Major cross-platform release

## License

Copyright (c) 2026 myTech.Today. All rights reserved.

This software is proprietary and confidential. Unauthorized copying, distribution, or use is strictly prohibited.

## About myTech.Today

myTech.Today provides professional IT services in Omaha and Lincoln, Nebraska.

### 🛠️ Our Services

- IT Consulting and Support
- Custom PowerShell Automation and Scripting
- Infrastructure Optimization and System Administration
- Cloud Integration (Azure, AWS, GCS, Microsoft 365)
- Network Design and Management
- Cybersecurity and Compliance Solutions
- Database Management and Custom Development
- System Setup, Upgrades, and Troubleshooting
- Virus and Spyware Removal
- Hardware Procurement, Installation, and Configuration

### 📍 Service Area

- Omaha, NE
- Lincoln, NE

### ⭐ Why Choose myTech.Today?

- 20+ years of IT consulting and software development experience
- Personalized service to 190+ satisfied clients
- 5-star review rating with consistent 24-hour solution delivery
- Payment-upon-success terms available
- Expertise in Windows automation, PowerShell scripting, and system optimization

### 📬 Contact Information

- Email: [sales@mytech.today](mailto:sales@mytech.today)
- Website: [mytech.today](https://mytech.today)
- GitHub: [@mytech-today-now](https://github.com/mytech-today-now)
- LinkedIn: [linkedin.com/in/kylerode](https://linkedin.com/in/kylerode)

**myTech.Today** · Professional IT Services · Serving Omaha and Lincoln · [mytech.today](https://mytech.today)

---

**Last Updated:** 2026-11-11
**Version:** 2.0.6 (GUI) / 2.0.2 (CLI)
**Maintained by:** [myTech.Today](https://mytech.today)
