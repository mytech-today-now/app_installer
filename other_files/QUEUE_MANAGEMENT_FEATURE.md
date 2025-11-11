# Installation Queue Management Feature

## Overview

The Installation Queue Management feature provides advanced control over batch installations, allowing users to review, reorder, pause, resume, and skip applications during the installation process.

## Version

- **Feature Added:** Version 1.4.0
- **Date:** November 10, 2025
- **Previous Version:** 1.3.9 (Search & Filter feature)

---

## Features

### 1. Queue Management Dialog

Before installation begins, users can manage the installation queue through an interactive dialog:

- **View Queue:** See all applications that will be installed in order
- **Reorder Applications:** Change installation order using:
  - Move Up button
  - Move Down button
  - Move to Top (Prioritize) button
- **Remove Applications:** Remove apps from the queue without unchecking them
- **Queue Preview:** See application name, category, and position in queue

### 2. Pause/Resume Functionality

During installation, users can pause and resume the process:

- **Pause Button:** Temporarily stops installation after current app completes
- **Resume Button:** Continues installation from where it was paused
- **State Persistence:** Queue state is saved when paused
- **Visual Feedback:** Button changes color and text to indicate state

### 3. Skip Functionality

Users can skip the currently installing application:

- **Skip Current Button:** Skips the current installation and moves to next app
- **Skip Tracking:** Skipped applications are counted and reported separately
- **Visual Indication:** Skipped apps are marked in the ListView

### 4. Queue State Persistence

Installation queue state is automatically saved and can be resumed:

- **Auto-Save:** Queue state saved after each installation
- **Resume on Restart:** If interrupted, queue can be restored on next run
- **State File:** `C:\mytech.today\app_installer\queue-state.json`
- **State Contents:**
  - Queue order
  - Current position
  - Pause state
  - Timestamp

### 5. Estimated Time Remaining (ETA)

Real-time calculation of remaining installation time:

- **Average-Based:** Calculates based on average installation time
- **Dynamic Updates:** Updates after each installation
- **Display Format:** Shows minutes remaining in progress label

---

## User Experience

### Installation Workflow

1. **Select Applications:** Check applications to install
2. **Click "Install Selected":** Triggers installation process
3. **Confirm Installation:** Review selected applications
4. **Manage Queue:** Queue management dialog appears
   - Review installation order
   - Reorder if needed (O&O ShutUp10 automatically prioritized)
   - Remove unwanted apps
   - Click OK to proceed or Cancel to abort
5. **Monitor Progress:** Installation begins
   - Pause/Resume and Skip buttons appear
   - Progress bar and ETA display
   - Real-time status updates
6. **Completion:** Summary shows success/failed/skipped counts

### Queue Management Dialog

```
┌─────────────────────────────────────────────────────────┐
│ Manage Installation Queue                              │
├─────────────────────────────────────────────────────────┤
│ #  │ Application        │ Category                     │
│ 1  │ O&O ShutUp10       │ Privacy & Security           │
│ 2  │ Google Chrome      │ Browsers                     │
│ 3  │ 7-Zip              │ Compression                  │
│ 4  │ VLC Media Player   │ Media Players                │
│ 5  │ Visual Studio Code │ Development                  │
├─────────────────────────────────────────────────────────┤
│                                    [Move Up]            │
│                                    [Move Down]          │
│                                    [Move to Top]        │
│                                    [Remove from Queue]  │
│                                                         │
│                                    [OK]  [Cancel]       │
└─────────────────────────────────────────────────────────┘
```

### During Installation

```
┌─────────────────────────────────────────────────────────┐
│ Installing Google Chrome (2 of 5 - 40%)...             │
│ Progress: ████████░░░░░░░░░░░░ 40% | ETA: 3.5 min      │
│                                                         │
│ [Pause]  [Skip Current]                                │
└─────────────────────────────────────────────────────────┘
```

---

## Technical Implementation

### Script Variables

```powershell
$script:InstallationQueue = @()  # Array of apps in installation queue
$script:QueueStatePath = "C:\mytech.today\app_installer\queue-state.json"
$script:IsPaused = $false  # Pause state flag
$script:SkipCurrent = $false  # Skip current installation flag
$script:CurrentQueueIndex = 0  # Current position in queue
```

### Core Functions

#### Save-QueueState

Saves the current queue state to JSON file for persistence.

```powershell
function Save-QueueState {
    # Creates state object with:
    # - Version
    # - Timestamp
    # - CurrentIndex
    # - IsPaused
    # - Queue (array of app objects)
    
    # Saves to: C:\mytech.today\app_installer\queue-state.json
}
```

#### Load-QueueState

Loads a previously saved queue state from JSON file.

```powershell
function Load-QueueState {
    # Restores:
    # - Installation queue
    # - Current index
    # - Pause state
    
    # Returns: $true if loaded successfully, $false otherwise
}
```

#### Clear-QueueState

Removes the queue state file after successful completion.

```powershell
function Clear-QueueState {
    # Deletes: C:\mytech.today\app_installer\queue-state.json
}
```

#### Show-QueueManagementDialog

Displays the queue management dialog with reordering capabilities.

```powershell
function Show-QueueManagementDialog {
    param([array]$Queue)
    
    # Creates Windows Forms dialog with:
    # - ListView showing queue
    # - Move Up/Down buttons
    # - Move to Top button
    # - Remove from Queue button
    # - OK/Cancel buttons
    
    # Returns: Modified queue array or $null if cancelled
}
```

### Installation Loop

The installation loop has been refactored to use the queue system:

```powershell
while ($script:CurrentQueueIndex -lt $script:InstallationQueue.Count) {
    # Check if paused
    while ($script:IsPaused) {
        # Wait for resume
        Save-QueueState
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 500
    }
    
    # Get current app from queue
    $app = $script:InstallationQueue[$script:CurrentQueueIndex]
    
    # Install (unless skipped)
    if (-not $script:SkipCurrent) {
        $success = Install-Application -App $app
    }
    
    # Update progress and save state
    $script:CurrentQueueIndex++
    Save-QueueState
}
```

---

## Queue State File Format

The queue state is saved as JSON:

```json
{
  "Version": "1.4.0",
  "Timestamp": "2025-11-10 14:30:45",
  "CurrentIndex": 2,
  "IsPaused": false,
  "Queue": [
    {
      "Name": "O&O ShutUp10",
      "ScriptName": "ooshutup10.ps1",
      "WingetId": "OOSoftware.ShutUp10",
      "Category": "Privacy & Security",
      "Description": "Free privacy tool for Windows"
    },
    {
      "Name": "Google Chrome",
      "ScriptName": "chrome.ps1",
      "WingetId": "Google.Chrome",
      "Category": "Browsers",
      "Description": "Fast, secure web browser by Google"
    }
  ]
}
```

---

## Benefits

1. **Better Control:** Users can review and modify installation order before starting
2. **Flexibility:** Pause/resume allows handling interruptions gracefully
3. **Efficiency:** Skip unwanted installations without cancelling entire batch
4. **Reliability:** State persistence prevents data loss on interruption
5. **Transparency:** Clear visibility into what will be installed and in what order
6. **Time Management:** ETA helps users plan their time

---

## Future Enhancements

Potential improvements for future versions:

1. **Drag-and-Drop Reordering:** Visual drag-drop in queue dialog
2. **Queue Templates:** Save and load common installation queues
3. **Priority Rules:** Auto-prioritize based on dependencies
4. **Batch Operations:** Select multiple items to move/remove
5. **Queue Import/Export:** Share queues between systems
6. **Installation Profiles:** Predefined queues for different scenarios

---

## Related Features

- **Search & Filter (v1.3.9):** Find applications to add to queue
- **.NET Framework Auto-Install (v1.3.8):** Ensures prerequisites
- **Progress Tracking:** Real-time status and ETA display
- **Centralized Logging:** All queue operations logged

---

This feature significantly enhances the user experience by providing professional-grade installation queue management capabilities comparable to enterprise software deployment tools.

