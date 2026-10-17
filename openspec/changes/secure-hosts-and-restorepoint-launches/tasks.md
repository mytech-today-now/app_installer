# Tasks: Secure remote helper launches

Beads issue: `app_installer-u58`. OpenSpec change: `secure-hosts-and-restorepoint-launches`.

- [x] Add a shared trust module with null production pins, immutable URI validation, exact-byte SHA-256 checking, parse validation, and injectable download and process boundaries.
- [x] Update both app scripts to use the trust gate, preserve current actions and arguments, remove policy overrides, and fail closed before persistent side effects when pins are absent.
- [x] Add offline coverage for missing and malformed pins, changed bytes, invalid sources, unavailable source, non-execution of rejected content, argument forwarding, and native exit codes.
- [x] Update README and changelog guidance without changing application versions or claiming live verification.
- [x] Update the syntax smoke list, run focused tests, run both available PowerShell syntax checks, and scan changed files for em dash characters.
