# Design

## Context

`builds/install-GUI.exe` is tracked since commit `81952a64201bbadf4418922953890497157db669` and last changed in `96b07b97894988a00660d967c53d4623a3e83115`. Its current SHA-256 is pinned by `tools/installer-exe-build.json`, and the builder uses it as an IExpress seed. The repository does not establish the seed's original source or release provenance. `builds/new/install-gui.exe` is tracked since `737cb1c01964a0743c4eb815e46fcfde4a3e15a8`, has Internet Explorer version resources, and has no identified current consumer or source recipe. Its origin and runtime requirements remain unknown.

The current build contract produces an unsigned IExpress package at `builds/generated/AppInstaller-<GUI-version>-win-x64.exe`. It does not bundle PowerShell. The versioned release workflow selects this path and its adjacent `.build.json` manifest. Local Git history contains no release tags, which does not establish whether a remote release exists.

## Goals / Non-Goals

**Goals:**

- Preserve both tracked executables byte for byte and record their roles and evidence limits.
- Reject either legacy path as a build destination, even when a legacy file is absent.
- Identify current build output with a stable artifact identity in its provenance manifest.
- Keep release input selection fixed to the versioned output and require its adjacent current build manifest and matching digest.
- Explain current release prerequisites separately from unsupported or unknown legacy artifacts.

**Non-Goals:**

- Executing, renaming, deleting, or replacing either legacy executable.
- Claiming the older seed's original source, an external distribution path, or a remote release history without evidence.
- Converting the current IExpress package into a self-contained executable or changing its runtime prerequisites.
- Publishing a release or recommending removal of either file.

## Decisions

1. **Store artifact identity in the existing build configuration.** Add a current release identity and a legacy artifact inventory with repository path, SHA-256, available version metadata, release eligibility, tracked history, current role, and provenance status. Treat the first binary's original origin and the second binary's origin as unknown.
2. **Protect paths, not just currently existing files.** Pass every inventory path to the output-path assertion. It rejects path equality before checking for existing files, so an explicit `-OutputPath` cannot reuse a legacy filename.
3. **Bind release validation to the builder manifest.** Record the configured current artifact identity in `.build.json`. Asset preparation requires this identity, the exact versioned filename, the adjacent `.build.json`, matching bytes, and the unsigned x64 contract. The release preparation entry point uses the configured generated directory and does not scan for executable files.
4. **Keep the user-facing support claim narrow.** The supported distribution is the versioned package produced by the current workflow and published with its checksum and release manifest. It remains an unsigned IExpress launcher without bundled PowerShell. The legacy seed is a build input, not a supported download. The other tracked executable remains unsupported with unknown prerequisites.
5. **Test bytes and selection without launching files.** Focused tests compare recorded hashes to tracked files, reject both legacy output paths, reject a missing or incorrect artifact identity, and verify the exact versioned asset allowlist.

## Risks / Trade-offs

- The first executable's source before its use as a pinned seed remains unknown. A pinned hash protects the expected bytes but does not authenticate their original publisher.
- The second executable's Internet Explorer version resources do not prove its contents, origin, use, or prerequisites.
- A local absence of tags does not prove that no remote release was ever published.
- The release name can be mistaken for a standalone runtime. Documentation must state that PowerShell remains a prerequisite and that the GUI has the additional runtime requirements in `compatibility.json`.

## Migration Plan

1. Preserve both files and their existing names. Mark the first as a non-distributable legacy seed and the second as an unverified legacy executable.
2. Build current packages only to the versioned generated path. Continue distributing only the matching versioned executable and its release metadata when a release is actually published.
3. Keep both legacy files until a future review establishes ownership, external consumers, and release evidence. No removal is authorized by this change.

## Open Questions

The original source and external distribution history for both legacy files are unknown. The current release workflow's external publication state is not established by local Git refs. These questions do not block labeling and path protection.
