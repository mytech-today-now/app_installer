#!/bin/bash
# ============================================================================
#  myTech.Today - App Installer Setup 
#  Checks for PowerShell 7+, installs if needed, then runs the installer
# ============================================================================

set -e

echo ""
echo "============================================================"
echo "  myTech.Today - App Installer Setup"
echo "============================================================"
echo ""

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "$SCRIPT_DIR/app-installer-cli.ps1" ]]; then
    echo "[ERROR] App Installer CLI script was not found: $SCRIPT_DIR/app-installer-cli.ps1" >&2
    exit 2
fi

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if PowerShell 7+ is installed
if command_exists pwsh; then
    echo "[OK] PowerShell 7+ is installed"
else
    echo "[INFO] PowerShell 7+ not found. Installing..."
    echo ""
    
    # Detect OS and install PowerShell
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command_exists brew; then
            echo "[INFO] Installing PowerShell via Homebrew..."
            brew install --cask powershell
        else
            echo "[ERROR] Homebrew not found. Please install Homebrew first:"
            echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
            echo ""
            echo "Then run: brew install --cask powershell"
            exit 1
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux - detect distro
        if command_exists apt-get; then
            echo "[INFO] Installing PowerShell via apt..."
            if [ "$EUID" -ne 0 ]; then
                echo "[WARN] Requesting sudo privileges..."
                sudo apt-get update && sudo apt-get install -y powershell
            else
                apt-get update && apt-get install -y powershell
            fi
        elif command_exists dnf; then
            echo "[INFO] Installing PowerShell via dnf..."
            if [ "$EUID" -ne 0 ]; then
                sudo dnf install -y powershell
            else
                dnf install -y powershell
            fi
        elif command_exists pacman; then
            echo "[INFO] Installing PowerShell via pacman..."
            if [ "$EUID" -ne 0 ]; then
                sudo pacman -S --noconfirm powershell
            else
                pacman -S --noconfirm powershell
            fi
        else
            echo "[ERROR] Could not detect package manager."
            echo "Please install PowerShell manually:"
            echo "  https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-linux"
            exit 1
        fi
    else
        echo "[ERROR] Unsupported operating system: $OSTYPE"
        exit 1
    fi
    
    # Verify installation
    if ! command_exists pwsh; then
        echo "[ERROR] PowerShell installation failed."
        exit 1
    fi
    
    echo ""
    echo "[OK] PowerShell 7 installed successfully!"
fi

echo ""
echo "[INFO] Running App Installer..."
echo ""

# Run the PowerShell installer script
policy_error_file="$(mktemp "${TMPDIR:-/tmp}/app-installer-launch.XXXXXX")" || {
    echo "[ERROR] Could not prepare temporary launch diagnostics." >&2
    exit 2
}
trap 'rm -f "$policy_error_file"' EXIT

if pwsh -NoProfile -File "$SCRIPT_DIR/app-installer-cli.ps1" "$@" 2>"$policy_error_file"; then
    installer_rc=0
else
    installer_rc=$?
fi

if [[ -s "$policy_error_file" ]]; then
    cat "$policy_error_file" >&2
    if grep -Eiq 'execution policy|running scripts is disabled|not digitally signed' "$policy_error_file"; then
        echo "PowerShell policy prevented this script from starting. No policy setting was changed. Use the signed release or contact your administrator." >&2
        echo "Signature guidance: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_signing?view=powershell-7.5" >&2
    fi
fi

if [[ "$installer_rc" -ne 0 ]]; then
    echo "[ERROR] Installer exited with code: $installer_rc" >&2
    exit "$installer_rc"
fi

echo ""
echo "[INFO] Setup complete."

