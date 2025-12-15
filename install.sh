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
pwsh -NoProfile -ExecutionPolicy Bypass -File "$SCRIPT_DIR/install.ps1" "$@"

echo ""
echo "[INFO] Setup complete."

