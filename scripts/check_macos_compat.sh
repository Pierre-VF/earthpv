#!/usr/bin/env bash
# Check macOS compatibility for EarthPV
#
# This script checks if your macOS system has the necessary tools and
# configuration to run EarthPV with the macOS compatibility layer.

set -euo pipefail

echo "=========================================="
echo "  EarthPV macOS Compatibility Check"
echo "=========================================="
echo ""

# Detect OS
OS_TYPE=$(uname -s)
echo "Detected OS: $OS_TYPE"

if [ "$OS_TYPE" != "Darwin" ]; then
  echo "ERROR: This is a macOS compatibility check, but your system is not macOS."
  echo "       This script is meant to be run on macOS only."
  exit 1
fi

# Check architecture
ARCH=$(uname -m)
echo "Architecture: $ARCH"
echo ""

# Track pass/fail
PASS=0
FAIL=0

check_command() {
  local cmd="$1"
  local description="$2"
  if command -v "$cmd" &>/dev/null; then
    echo "✓ $description ($cmd)"
    ((PASS++))
  else
    echo "✗ $description ($cmd) - NOT FOUND"
    ((FAIL++))
  fi
}

check_python_package() {
  local package="$1"
  local description="$2"
  if python3 -c "import $package" 2>/dev/null; then
    echo "✓ $description ($package)"
    ((PASS++))
  else
    echo "✗ $description ($package) - NOT INSTALLED"
    ((FAIL++))
  fi
}

check_file() {
  local file="$1"
  local description="$2"
  if [ -f "$file" ]; then
    echo "✓ $description ($file)"
    ((PASS++))
  else
    echo "✗ $description ($file) - NOT FOUND"
    ((FAIL++))
  fi
}

echo "Checking basic system tools..."
echo "-------------------------------------------"

check_command "bash" "Bash shell"|| true
check_command "python3" "Python 3"|| true
check_command "pip" "Pip package manager"|| true
check_command "stat" "stat command"|| true
check_command "df" "df command"|| true
check_command "nohup" "nohup command"|| true
check_command "pgrep" "pgrep command"|| true
check_command "pkill" "pkill command"|| true
check_command "awk" "awk command"|| true
check_command "grep" "grep command"|| true
check_command "sed" "sed command"|| true

echo ""
echo "Checking optional GNU tools (recommended)..."
echo "-------------------------------------------"

# Check for GNU tools (preferred for consistency)
check_command "gstat" "GNU stat"|| true
check_command "greadlink" "GNU readlink"|| true
check_command "ggrep" "GNU grep"|| true
check_command "gsed" "GNU sed"|| true
check_command "gawk" "GNU awk"|| true

echo ""
echo "Checking Python packages..."
echo "-------------------------------------------"

# Check if we can import the earthpv module
if [ -d "src/earthpv" ]; then
  cd "$(dirname "$0")/.."
  if [ -f "pixi.toml" ]; then
    echo "✓ pixi.toml found - EarthPV project detected"
    ((PASS++))
  fi
  
  # Try to import earthpv
  if python3 -c "import sys; sys.path.insert(0, 'src'); import earthpv" 2>/dev/null; then
    echo "✓ earthpv module can be imported"
    ((PASS++))
  else
    echo "✗ earthpv module cannot be imported - NOT INSTALLED"
    ((FAIL++))
  fi
fi

echo ""
echo "Checking macOS compatibility layer..."
echo "-------------------------------------------"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/macos_compat.sh" ]; then
  echo "✓ macos_compat.sh found"
  ((PASS++))
  
  # Try to source and test it
  if source "$SCRIPT_DIR/macos_compat.sh" 2>/dev/null; then
    echo "✓ macos_compat.sh can be sourced"
    ((PASS++))
    
    # Test some functions
    if command -v stat_file_mtime &>/dev/null; then
      echo "✓ stat_file_mtime function available"
      ((PASS++))
    fi
    if command -v realpath &>/dev/null; then
      echo "✓ realpath function available"
      ((PASS++))
    fi
    if command -v unit_active &>/dev/null; then
      echo "✓ unit_active function available"
      ((PASS++))
    fi
  else
    echo "✗ macos_compat.sh cannot be sourced - SYNTAX ERROR"
    ((FAIL++))
  fi
else
  echo "✗ macos_compat.sh not found - COMPATIBILITY LAYER NOT INSTALLED"
  ((FAIL++))
fi

echo ""
echo "Checking pixi configuration..."
echo "-------------------------------------------"

if [ -f "pixi.toml" ]; then
  # Check if macOS platforms are configured
  if grep -q "osx-arm64\|osx-64" pixi.toml; then
    echo "✓ macOS platforms configured in pixi.toml"
    ((PASS++))
  else
    echo "⚠ macOS platforms not found in pixi.toml"
    echo "  You may need to add: platforms = [\"linux-64\", \"osx-arm64\", \"osx-64\"]"
    ((FAIL++))
  fi
  
  # Check if pixi is installed
  if command -v pixi &>/dev/null; then
    echo "✓ pixi command available"
    ((PASS++))
  else
    echo "✗ pixi not installed - Install with: brew install pixi"
    ((FAIL++))
  fi
fi

echo ""
echo "Checking disk space..."
echo "-------------------------------------------"

# Check root disk
ROOT_FREE=$(df -h / | awk 'NR==2 {print $4}' | sed 's/[^0-9.]//g' | cut -d. -f1)
echo "Free space on /: ${ROOT_FREE}G"

if [ "$ROOT_FREE" -ge 10 ] 2>/dev/null; then
  echo "✓ Sufficient disk space on root (>= 10G)"
  ((PASS++))
else
  echo "⚠ Low disk space on root (< 10G) - Some operations may fail"
  ((FAIL++))
fi

echo ""
echo "Checking Homebrew (optional but recommended)..."
echo "-------------------------------------------"

if command -v brew &>/dev/null; then
  echo "✓ Homebrew installed"
  ((PASS++))
  
  # Check for useful Homebrew packages
  if brew list --formula | grep -q "^coreutils$"; then
    echo "✓ GNU coreutils installed"
    ((PASS++))
  else
    echo "  Consider installing: brew install coreutils"
  fi
else
  echo "  Homebrew not installed"
  echo "  Consider installing for easier package management"
fi

echo ""
echo "=========================================="
echo "  Summary"
echo "=========================================="
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo ""

if [ "$FAIL" -eq 0 ]; then
  echo "✓ All checks passed! Your system is ready for EarthPV on macOS."
  exit 0
elif [ "$FAIL" -le 3 ]; then
  echo "⚠ Some optional checks failed. EarthPV may work with limitations."
  exit 0
else
  echo "✗ Multiple checks failed. Please address the issues above."
  exit 1
fi
