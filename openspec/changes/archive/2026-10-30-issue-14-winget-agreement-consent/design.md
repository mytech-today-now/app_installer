# Design: WinGet agreement consent

## Product policy

Selecting an app means the user wants the install or update operation. It does not authorize acceptance of the package owner's terms or a WinGet source's terms. WinGet remains responsible for displaying the applicable agreement text and collecting the user's yes/no choice in an interactive install or upgrade.

The App Installer does not add agreement acceptance switches after that choice. WinGet persists source agreement acceptance according to its own behavior. The App Installer does not create a standing package-agreement consent record; a package agreement that blocks an unattended run stays blocked.

## Interactive commands

Interactive WinGet install and package-specific upgrade commands omit both acceptance switches. The process boundary streams review output to the current UI without writing agreement text to installer logs. Agreement-specific failures stop automatic retries. The GUI offers to open a visible WinGet window and rerun the same validated command without acceptance switches; WinGet asks for the final decision there. The CLI reports the review requirement and lets the user retry explicitly.

## Noninteractive commands

Installed-app discovery, dependency discovery, update discovery, and the monthly task use `--disable-interactivity` without acceptance switches. A package or source agreement requirement therefore remains a failure. Monthly task results preserve the native agreement exit code and report the package as failed/incomplete without storing or logging agreement text.

## Offline evidence

Fake WinGet output covers success without agreements, package agreement requirements, source agreement requirements, and a declined agreement. Tests assert exact argv, a single attempt after decline, failed scheduled results, and no acceptance switches. No fixture represents a real user consent or invokes a live package manager.
