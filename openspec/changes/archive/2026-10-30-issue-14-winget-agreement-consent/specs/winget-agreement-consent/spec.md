# Spec Delta

## Purpose

Defines explicit handling of WinGet package and source agreements for interactive app operations and unattended monthly updates.

## ADDED Requirements

### Requirement: Application selection does not accept WinGet agreements

The App Installer MUST NOT treat selecting an application as consent to package or source terms. It MUST NOT pass agreement acceptance switches automatically.

#### Scenario: Application selection requests an operation

- **WHEN** a user selects an application to install or update
- **THEN** the App Installer requests that operation without accepting package or source terms

### Requirement: Interactive commands request an explicit agreement decision

Interactive install and package-specific upgrade commands MUST allow WinGet to display required terms and collect the user's yes/no choice. If the native prompt cannot be used in the current UI, the App Installer MUST provide a visible review/retry path that does not pre-accept terms. Agreement text MUST NOT be written to installer log files.

#### Scenario: No agreement is required

- **WHEN** WinGet reports a successful install or upgrade without an agreement requirement
- **THEN** the App Installer reports the fake or native command result without adding agreement acceptance switches

#### Scenario: Package agreement is required

- **WHEN** WinGet requires package agreement review
- **THEN** the package terms are shown through WinGet's interactive review and the App Installer waits for the user's explicit decision

#### Scenario: Source agreement is required

- **WHEN** WinGet requires source agreement review
- **THEN** the source terms are shown through WinGet's interactive review and the App Installer waits for the user's explicit decision

#### Scenario: WinGet cannot obtain a decision in the current UI

- **WHEN** the current UI cannot present WinGet's native agreement prompt
- **THEN** the App Installer offers a visible WinGet review/retry path without accepting the agreement

#### Scenario: User declines

- **WHEN** the user declines an agreement or WinGet cannot obtain an explicit decision
- **THEN** the App Installer does not retry or accept terms automatically and reports that the operation did not complete

### Requirement: Unattended updates fail closed on agreement requirements

The monthly update task MUST disable interactivity and MUST NOT pass package or source agreement acceptance switches. A package update that requires an agreement MUST be reported as failed or incomplete with the native exit code and without logging agreement text.

#### Scenario: Scheduled update needs package or source terms

- **WHEN** a scheduled package update returns a package- or source-agreement-required exit code
- **THEN** the task reports that package as failed, returns a non-success outcome, and performs no agreement retry

### Requirement: Discovery never accepts agreements

Installed-app, dependency, and update-discovery queries MUST NOT accept source or package agreements. Queries that can encounter a source agreement MUST disable interactivity and treat that query as incomplete rather than consenting during discovery.

#### Scenario: Discovery encounters new source terms

- **WHEN** a discovery query requires source agreement review
- **THEN** the query stops without acceptance and package detection or update discovery remains incomplete
