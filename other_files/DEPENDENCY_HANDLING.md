# Automatic Dependency Handling

## Overview

Both `install-gui.ps1` and `install.ps1` now include **automatic dependency detection and installation** to ensure seamless application installations and updates without user interruption.

---

## Problem Statement

Many applications require dependencies to function properly. For example:
- **LibreOffice** requires `Microsoft.VCRedist.2015+.x64` (Visual C++ Redistributable)
- **Other applications** may require .NET Framework, DirectX, or other runtime libraries

Previously, if dependencies were missing:
- ❌ Installations could fail with cryptic error messages
- ❌ Users had to manually identify and install dependencies
- ❌ The installation process was interrupted
- ❌ No visibility into what dependencies were needed

---

## Solution

### Automatic Dependency Management

The scripts now:
1. ✅ **Detect dependencies** before installing/updating applications
2. ✅ **Check if dependencies are already installed**
3. ✅ **Automatically install missing dependencies**
4. ✅ **Log all dependency operations** for transparency
5. ✅ **Handle errors gracefully** without interrupting the user experience
6. ✅ **Continue even if dependency installation fails** (winget will retry)

---

## How It Works

### 1. Dependency Detection

**Function**: `Get-PackageDependencies`

```powershell
$dependencies = Get-PackageDependencies -PackageId "TheDocumentFoundation.LibreOffice"
# Returns: @("Microsoft.VCRedist.2015+.x64")
```

**Process**:
1. Queries `winget show --id {PackageId}` to get package details
2. Parses the output to extract the "Package Dependencies" section
3. Returns an array of dependency package IDs
4. Logs all findings to the log file

**Example Output**:
```
Dependencies found: 1
  - Microsoft.VCRedist.2015+.x64
```

---

### 2. Dependency Installation

**Function**: `Install-PackageDependencies`

```powershell
$success = Install-PackageDependencies -Dependencies @("Microsoft.VCRedist.2015+.x64") -PackageName "LibreOffice"
```

**Process**:
1. **Check if already installed**: Uses `winget list --id {DependencyId} --exact`
2. **Skip if installed**: Logs and displays "[OK] {Dependency} (already installed)"
3. **Install if missing**: Uses `winget install --id {DependencyId} --silent`
4. **Log results**: Records success/failure in the log file
5. **Continue on failure**: Doesn't block the main installation (winget will retry)

**Example Output**:
```
[DEPS] Checking 1 dependencies...
[OK] Microsoft.VCRedist.2015+.x64 (already installed)
```

Or if not installed:
```
[DEPS] Checking 1 dependencies...
[INSTALL] Installing Microsoft.VCRedist.2015+.x64...
[OK] Microsoft.VCRedist.2015+.x64 installed successfully
```

---

### 3. Integration Points

#### A. Application Installation (`Install-Application`)

**Location**: 
- `install-gui.ps1` lines 2450-2470
- `install.ps1` lines 2142-2178

**When**: Before downloading/installing the main application

```powershell
# Check and install dependencies first
$dependencies = Get-PackageDependencies -PackageId $App.WingetId
if ($dependencies.Count -gt 0) {
    Write-Log "Package $($App.Name) has $($dependencies.Count) dependencies" -Level INFO
    Install-PackageDependencies -Dependencies $dependencies -PackageName $App.Name | Out-Null
}

# Then install the main application
$result = winget install --id $App.WingetId --silent ...
```

#### B. Application Updates (`Update-Applications`)

**Location**:
- `install-gui.ps1` lines 2045-2071
- `install.ps1` lines 1598-1626

**When**: Before upgrading the application

```powershell
# Check and install dependencies first
$dependencies = Get-PackageDependencies -PackageId $update.Id
if ($dependencies.Count -gt 0) {
    Write-Log "Package $($update.Name) has $($dependencies.Count) dependencies" -Level INFO
    Install-PackageDependencies -Dependencies $dependencies -PackageName $update.Name | Out-Null
}

# Then upgrade the application
$output = & cmd /c "winget upgrade --id `"$($update.Id)`" --silent ..."
```

---

## User Experience

### GUI Mode (`install-gui.ps1`)

**During Installation**:
```
[UPDATE] Updating LibreOffice...
  [DEPS] Checking 1 dependencies...
  [OK] Microsoft.VCRedist.2015+.x64 (already installed)
  [DOWNLOAD] Downloading LibreOffice...
  [OK] LibreOffice installed successfully!
```

**If Dependency Needs Installation**:
```
[UPDATE] Updating LibreOffice...
  [DEPS] Checking 1 dependencies...
  [INSTALL] Installing Microsoft.VCRedist.2015+.x64...
  [OK] Microsoft.VCRedist.2015+.x64 installed successfully
  [DOWNLOAD] Downloading LibreOffice...
  [OK] LibreOffice installed successfully!
```

### CLI Mode (`install.ps1`)

**Same experience with color-coded output**:
- Gray: Informational messages
- Cyan: Dependency installation in progress
- Green: Success
- Yellow: Warnings (dependency failed but continuing)

---

## Logging

All dependency operations are logged to `C:\mytech.today\logs\`:

```
[INFO] Checking dependencies for package: TheDocumentFoundation.LibreOffice
[INFO] Found dependency: Microsoft.VCRedist.2015+.x64
[INFO] Package TheDocumentFoundation.LibreOffice has 1 package dependencies
[INFO] Installing dependencies for LibreOffice...
[INFO] Checking dependency: Microsoft.VCRedist.2015+.x64
[INFO] Dependency Microsoft.VCRedist.2015+.x64 is already installed
```

Or if installation is needed:
```
[INFO] Checking dependency: Microsoft.VCRedist.2015+.x64
[INFO] Installing dependency: Microsoft.VCRedist.2015+.x64
[SUCCESS] Successfully installed dependency: Microsoft.VCRedist.2015+.x64
```

---

## Error Handling

### Graceful Degradation

If dependency installation fails:
1. ✅ **Log the warning** (not an error)
2. ✅ **Display warning message** to user
3. ✅ **Continue with main installation** (don't block)
4. ✅ **Let winget retry** (winget will attempt to install dependencies again)

**Example**:
```
[DEPS] Checking 1 dependencies...
[INSTALL] Installing Microsoft.VCRedist.2015+.x64...
[WARN] Microsoft.VCRedist.2015+.x64 installation failed (continuing anyway)
[DOWNLOAD] Downloading LibreOffice...
```

### Why Continue on Failure?

- Winget has built-in dependency handling with `--skip-dependencies` flag (default: enabled)
- Winget will attempt to install dependencies again during the main installation
- Some dependencies might already be satisfied by different package versions
- Prevents blocking the entire installation process for optional dependencies

---

## Benefits

### 1. **Seamless User Experience**
- No interruptions or manual intervention required
- Dependencies installed automatically in the background
- Clear progress indicators

### 2. **Transparency**
- Users see what dependencies are being installed
- Complete logging for troubleshooting
- Clear success/failure messages

### 3. **Reliability**
- Reduces installation failures due to missing dependencies
- Handles edge cases gracefully
- Continues even if dependency installation fails

### 4. **Maintainability**
- Centralized dependency handling logic
- Consistent behavior across GUI and CLI modes
- Easy to extend for future enhancements

---

## Technical Details

### Dependency Detection Regex

The function uses regex to parse winget's output:

```powershell
if ($outputStr -match "Dependencies:[\s\S]*?Package Dependencies:\s*\n([\s\S]*?)(?:\n\s*\n|\n[A-Z]|\z)") {
    $depsSection = $matches[1]
    # Parse individual dependency lines
}
```

**Matches**:
- `Dependencies:` - Section header
- `Package Dependencies:` - Subsection for package dependencies (not Windows Features)
- Captures everything until: empty line, new section (capital letter), or end of string

### Dependency ID Extraction

```powershell
$lines = $depsSection -split "`r?`n"
foreach ($line in $lines) {
    $line = $line.Trim()
    if ($line -and $line -notmatch "^\s*-" -and $line -match "^[A-Za-z0-9\.\+]+") {
        $dependencies += $line
    }
}
```

**Filters**:
- Non-empty lines
- Not starting with `-` (bullet points)
- Starting with alphanumeric characters (package IDs)

---

## Testing

### Test Case 1: LibreOffice Installation

**Expected Behavior**:
1. Detect `Microsoft.VCRedist.2015+.x64` dependency
2. Check if already installed
3. Install if missing
4. Install LibreOffice
5. Log all operations

**Test Command** (GUI):
```powershell
.\app_installer\install-gui.ps1
# Select LibreOffice → Click Install
```

**Test Command** (CLI):
```powershell
.\app_installer\install.ps1
# Select LibreOffice from the list
```

### Test Case 2: Update with Dependencies

**Expected Behavior**:
1. Check for updates
2. Detect dependencies for each update
3. Install missing dependencies
4. Update applications
5. Log all operations

**Test Command** (GUI):
```powershell
.\app_installer\install-gui.ps1
# Click "Check for Updates" → Select apps → Click "Update Selected"
```

### Test Case 3: Log Verification

**Expected Behavior**:
- All dependency checks logged
- All installation attempts logged
- Success/failure clearly indicated

**Test Command**:
```powershell
Get-Content "C:\mytech.today\logs\app_installer_gui_*.log" -Tail 100 | Select-String "dependency|Dependencies"
```

---

## Future Enhancements (Optional)

1. **Dependency Tree Visualization**: Show dependency hierarchy in GUI
2. **Dependency Caching**: Cache dependency check results to improve performance
3. **Parallel Dependency Installation**: Install multiple dependencies simultaneously
4. **Dependency Version Checking**: Verify minimum required versions
5. **Custom Dependency Sources**: Support dependencies from multiple sources

---

## Conclusion

The automatic dependency handling feature ensures:

✅ **Seamless installations** - No user intervention required  
✅ **Complete transparency** - Full logging and progress indicators  
✅ **Robust error handling** - Graceful degradation on failures  
✅ **Consistent behavior** - Same logic in GUI and CLI modes  
✅ **Professional experience** - Matches enterprise software standards  

Both `install-gui.ps1` and `install.ps1` now provide a professional, enterprise-grade installation experience with automatic dependency management.

