# GitHub release protection verification

## Current record

- **Repository:** `mytech-today-now/app_installer` (from the local `origin` remote)
- **Remote settings status:** NOT VERIFIED
- **Local access check timestamp:** `2026-10-30T00:05:58Z` (UTC; this is not a remote observation timestamp)
- **Remote observation timestamp:** NOT VERIFIED; no settings response was available to record.
- **Reason:** No GitHub CLI or authenticated read-only GitHub connector was available in the implementation environment. No remote settings were queried or changed.

| Remote setting | Observed value |
| --- | --- |
| Ruleset name/ID, source, and enforcement status | NOT VERIFIED |
| Target tag pattern and exclusions | NOT VERIFIED |
| Tag creation, update, and deletion restrictions | NOT VERIFIED |
| Required reviewers or approval control | NOT VERIFIED |
| Bypass actors and modes | NOT VERIFIED |
| Effective repository/organization workflow permission scope | NOT VERIFIED |

`NOT VERIFIED` means no remote value was observed; it does not mean that a rule or reviewer is absent.

The local workflow source does show a `v*` tag trigger, passes `github.ref_protected` to validation and publication, rejects a value other than `true`, grants workflow-level `contents: read`, and gives only the publishing job `contents: write`. These are local source observations. They do not establish the current GitHub ruleset or effective repository and organization Actions settings.

## Remote verification checklist

Complete this read-only review in GitHub before treating protected-tag publication as ready. Record the exact value for each item, an observation timestamp in UTC, and a durable evidence location. If an item does not apply or is not offered for tag rulesets, record that explicitly and name the control that covers the same risk.

- [ ] **Ruleset identity and enforcement:** Record every applicable repository, organization, or enterprise ruleset name and ID, source, target type, enforcement status (`active`, `evaluate`, or `disabled`), and any include/exclude patterns. Confirm the ruleset targets tags.
- [ ] **Tag pattern:** Record the exact remote pattern and exclusions. Compare it with the workflow trigger `v*` and confirm that the workflow's semantic-version validation is still the narrower acceptance gate.
- [ ] **Tag mutation controls:** Record whether matching tags have creation, update, and deletion restrictions, including any overlapping legacy tag protection rules. Confirm that release tags cannot be moved or deleted by ordinary actors.
- [ ] **Required reviewers and approval control:** Record the actual approval mechanism and required reviewers. GitHub documents required approvals as part of pull-request rules for branches; if the tag ruleset does not offer reviewer approval, record `N/A for tags` and separately record the default-branch review rules that gate changes to the release workflow. Do not count a branch review as approval of tag creation.
- [ ] **Bypass actors:** Record each bypass actor's exact user/team/app/role identity and bypass mode. Include inherited organization or enterprise rules. Confirm that every bypass is intentional and covered by the release approval process.
- [ ] **Workflow permission scope:** In repository **Settings > Actions > General**, record the effective default `GITHUB_TOKEN` permission (`read` or `write`) and whether Actions may approve pull requests. Record any organization policy that restricts or supplies these values. Compare them with the workflow's local `contents: read` default and publishing job's `contents: write` override; identify any other effective token scope.
- [ ] **Evidence and readiness:** Save a ruleset view or read-only API response showing the above values, together with the UTC observation time. Mark the remote status `VERIFIED` only after every applicable item has evidence; otherwise keep it `NOT VERIFIED` and list the missing evidence.

GitHub documents the [ruleset review page](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/managing-rulesets-for-a-repository), [tag and branch ruleset configuration](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository), [available tag rules](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets), and [repository Actions settings](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository). Those documents describe where to inspect the controls; they do not report this repository's settings.
