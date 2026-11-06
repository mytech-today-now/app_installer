# Design

## Context

The standard Windows build and release packaging runners use windows-2025, which is Windows Server 2025. The compatibility contract supports Windows 11 25H2 and 26H2 Home or Pro x64 clients. The workflow already labels client GUI checks NOT RUN on Server.

## Goals / Non-Goals

**Goals:**

- Validate a recorded client result for each supported PowerShell engine before publication.
- Bind each record to the exact release source SHA and the current compatibility contract.
- Keep manual client execution separate from Server build and metadata validation.

**Non-Goals:**

- Provision a Windows client, PowerShell engine, GUI runtime, or application.
- Treat a Server, ARM64, or unsupported Windows release as client evidence.
- Fetch or authenticate the contents at the recorded evidence location.

## Decisions

- Keep the machine-readable evidence file on the default branch and include the tested source SHA in each record. The tag workflow can then consume evidence recorded after the source commit without changing the commit being released. A tag-sourced checklist would create a revision cycle because recording test results would change the tagged commit.
- Use one validation module for the release job and offline fixture tests. It reads the evidence and compatibility JSON without querying the runner host, so running the metadata gate on Server cannot create client proof.
- Require a row for each exact engine, a supported client edition/release/build and x64 architecture, the corresponding GUI runtime and assembly identities, STA, PASS capability and isolated startup results, a UTC timestamp, and an evidence location. Reuse compatibility.json as the authority for versions, runtime thresholds, and servicing dates.
- Keep the evidence template explicitly NOT RUN and append completed revision-specific records. This makes the current release block visible and retains older evidence without reassigning it to a new source revision.

## Risks / Trade-offs

- The gate validates recorded claims and required fields but does not fetch or verify the evidence location. Protect default-branch changes and review the referenced client outputs before adding a record.
- A release remains blocked until an already-provisioned supported client can run both exact engines. Keep the checklist and evidence template NOT RUN rather than substituting Server results.
- The Windows runner image catalog can change. Recheck the official image list before replacing the manual path with a hosted runner.

## Migration Plan

1. Merge the gate and NOT RUN evidence template on the default branch.
2. Run both client checks against the exact source commit intended for release and append a revision-bound record to the default branch.
3. Push the protected tag to the tested commit. If the evidence record was not present when the workflow ran, add it and rerun the failed release workflow.

## Open Questions

None.
