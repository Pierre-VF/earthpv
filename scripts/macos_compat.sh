#!/usr/bin/env bash
# macOS Compatibility Layer for EarthPV
# 
# This file provides cross-platform functions that work on both Linux and macOS.
# Source this file in shell scripts that need macOS compatibility:
#   source "$(dirname "$0")/macos_compat.sh"
#
# The following functions provide macOS-compatible alternatives:
# - stat_file_mtime: Get file modification time in seconds since epoch
# - stat_file_size: Get file size in bytes
# - realpath: Canonicalize a path (resolve symlinks)
# - free_gb: Get available disk space in GB
# - unit_active: Check if a service/unit is running (Linux: systemctl, macOS: launchctl/pgrep)
# - start_unit: Start a background service (Linux: systemd-run, macOS: background process)
# - stop_unit: Stop a service (Linux: systemctl, macOS: pkill)
# - list_units: List active services (Linux: systemctl, macOS: pgrep)
#

set -uo pipefail

# Detect the operating system
get_os() {
  case "$(uname -s)" in
    Darwin)  echo "macos" ;;
    Linux)   echo "linux" ;;
    *)       echo "unknown" ;;
  esac
}

OS_TYPE=$(get_os)

# ============================================================================
# File system functions
# ============================================================================

# Get file modification time in seconds since epoch
# Linux: stat -c %Y
# macOS: stat -f %m
stat_file_mtime() {
  local file="$1"
  if [ "$OS_TYPE" = "linux" ]; then
    stat -c %Y "$file" 2>/dev/null || echo 0
  elif [ "$OS_TYPE" = "macos" ]; then
    stat -f %m "$file" 2>/dev/null || echo 0
  else
    echo 0
  fi
}

# Get file size in bytes
# Linux: stat -c %s
# macOS: stat -f %z
stat_file_size() {
  local file="$1"
  if [ "$OS_TYPE" = "linux" ]; then
    stat -c %s "$file" 2>/dev/null || echo 0
  elif [ "$OS_TYPE" = "macos" ]; then
    stat -f %z "$file" 2>/dev/null || echo 0
  else
    echo 0
  fi
}

# Canonicalize a path (resolve all symlinks)
# Linux: readlink -f
# macOS: Use Python or a while loop
realpath() {
  local path="$1"
  if [ "$OS_TYPE" = "linux" ]; then
    readlink -f "$path" 2>/dev/null || echo "$path"
  elif [ "$OS_TYPE" = "macos" ]; then
    # macOS doesn't have readlink -f, use Python if available
    if command -v python3 &>/dev/null; then
      python3 -c "import os; print(os.path.realpath('$path'))" 2>/dev/null || echo "$path"
    elif command -v python &>/dev/null; then
      python -c "import os; print(os.path.realpath('$path'))" 2>/dev/null || echo "$path"
    else
      # Fallback: use a while loop to resolve symlinks
      local resolved="$path"
      while [ -L "$resolved" ]; do
        local dir
        dir=$(dirname "$resolved")
        resolved=$(readlink "$resolved")
        # If relative symlink, prepend the directory
        case "$resolved" in
          /*) ;;  # absolute path
          *) resolved="$dir/$resolved" ;;
        esac
      done
      echo "$resolved"
    fi
  else
    echo "$path"
  fi
}

# Get available disk space in GB for a mount point
# Linux: df -BG --output=avail
# macOS: df -BG
free_gb() {
  local mount_point="$1"
  if [ "$OS_TYPE" = "linux" ]; then
    df -BG --output=avail "$mount_point" 2>/dev/null | tail -1 | tr -dc '0-9' || echo 0
  elif [ "$OS_TYPE" = "macos" ]; then
    # macOS df doesn't have --output, parse the standard output
    df -BG "$mount_point" 2>/dev/null | awk 'NR==2 {print $4}' | tr -dc '0-9' || echo 0
  else
    echo 0
  fi
}

# ============================================================================
# Process/Service management functions
# ============================================================================

# Check if a unit/service is active
# Linux: systemctl --user is-active --quiet <unit>
# macOS: pgrep -f <pattern> or launchctl
unit_active() {
  local unit="$1"
  if [ "$OS_TYPE" = "linux" ]; then
    systemctl --user is-active --quiet "$unit" 2>/dev/null
    return $?
  elif [ "$OS_TYPE" = "macos" ]; then
    # On macOS, check if a process with this unit name is running
    # Convert systemd unit name to a process pattern
    local pattern="${unit//-/_}"  # Replace hyphens with underscores for launchctl
    if pgrep -f "$unit" &>/dev/null; then
      return 0
    fi
    # Also check launchctl
    if launchctl list | grep -q "$pattern"; then
      return 0
    fi
    return 1
  else
    return 1
  fi
}

# Start a background unit/service
# Linux: systemd-run --user --collect --unit=<unit> -p WorkingDirectory=<dir> <command>
# macOS: Run in background with nohup
start_unit() {
  local unit="$1"
  local working_dir="$2"
  shift 2
  local command="$*"
  
  if [ "$OS_TYPE" = "linux" ]; then
    systemd-run --user --collect --unit="$unit" -p WorkingDirectory="$working_dir" $command >/dev/null
  elif [ "$OS_TYPE" = "macos" ]; then
    # On macOS, use nohup to run in background
    # Create a unique marker file
    local marker_dir="$HOME/.earthpv_units"
    mkdir -p "$marker_dir"
    local marker="$marker_dir/$unit.pid"
    
    # Kill any existing process with this unit name
    stop_unit "$unit" >/dev/null 2>&1
    
    # Run the command in background
    nohup bash -c "cd '\"$working_dir\"' && $command" > "$marker_dir/$unit.log" 2>&1 &
    local pid=$!
    echo "$pid" > "$marker"
    
    # Also try to register with launchctl for better process management
    if command -v launchctl &>/dev/null; then
      # Create a simple plist for launchctl (temporary agent)
      local plist_dir="$HOME/Library/LaunchAgents"
      local plist_file="$plist_dir/earthpv.$unit.plist"
      mkdir -p "$plist_dir"
      
      cat > "$plist_file" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>earthpv.$unit</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>-c</string>
    <string>cd "$working_dir" && $command</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>WorkingDirectory</key>
  <string>$working_dir</string>
  <key>StandardOutPath</key>
  <string>$marker_dir/$unit.log</string>
  <key>StandardErrorPath</key>
  <string>$marker_dir/$unit.err</string>
  <key>ProcessType</key>
  <string>Interactive</string>
</dict>
</plist>
EOF
      
      # Load the launchd job
      launchctl load "$plist_file" 2>/dev/null
    fi
  fi
}

# Stop a unit/service
# Linux: systemctl --user stop <unit>
# macOS: pkill or launchctl
stop_unit() {
  local unit="$1"
  if [ "$OS_TYPE" = "linux" ]; then
    systemctl --user stop "$unit" 2>/dev/null
  elif [ "$OS_TYPE" = "macos" ]; then
    # On macOS, kill processes matching the unit name
    local pattern="${unit//-/_}"
    
    # Try pkill first
    pkill -f "$unit" 2>/dev/null
    
    # Also try to unload from launchctl
    if command -v launchctl &>/dev/null; then
      launchctl unload "$HOME/Library/LaunchAgents/earthpv.$unit.plist" 2>/dev/null
      rm -f "$HOME/Library/LaunchAgents/earthpv.$unit.plist" 2>/dev/null
    fi
    
    # Remove marker files
    local marker_dir="$HOME/.earthpv_units"
    rm -f "$marker_dir/$unit.pid" "$marker_dir/$unit.log" "$marker_dir/$unit.err" 2>/dev/null
  fi
}

# List active units by pattern
# Linux: systemctl --user list-units --type=service --state=active --no-legend <pattern>
# macOS: pgrep
list_units() {
  local pattern="$1"
  if [ "$OS_TYPE" = "linux" ]; then
    systemctl --user list-units --type=service --state=active --no-legend "$pattern" 2>/dev/null | grep -q .
  elif [ "$OS_TYPE" = "macos" ]; then
    pgrep -f "$pattern" &>/dev/null
  else
    return 1
  fi
}

# Count active units matching a pattern
# Linux: systemctl --user list-units --type=service --state=active --no-legend <pattern> | wc -l
# macOS: pgrep | wc -l
n_units_active() {
  local pattern="$1"
  if [ "$OS_TYPE" = "linux" ]; then
    systemctl --user list-units --type=service --state=active --no-legend "$pattern" 2>/dev/null | wc -l
  elif [ "$OS_TYPE" = "macos" ]; then
    pgrep -f "$pattern" 2>/dev/null | wc -l
  else
    echo 0
  fi
}

# ============================================================================
# Utility: Clean up old earthpv units on macOS
# ============================================================================

cleanup_macos_units() {
  if [ "$OS_TYPE" = "macos" ]; then
    # Remove all earthpv-related launchd jobs
    if command -v launchctl &>/dev/null; then
      for plist in "$HOME/Library/LaunchAgents/"earthpv.*.plist; do
        [ -f "$plist" ] || continue
        local label=$(basename "$plist" .plist)
        launchctl unload "$plist" 2>/dev/null
        rm -f "$plist" 2>/dev/null
      done
    fi
    
    # Remove marker directory
    rm -rf "$HOME/.earthpv_units" 2>/dev/null
  fi
}

# Automatically clean up on script exit (optional, uncomment if needed)
# trap cleanup_macos_units EXIT
