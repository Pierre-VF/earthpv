# macOS Setup Guide for EarthPV

EarthPV is primarily developed and tested on Linux, but with some adjustments it can run on macOS as well. This guide explains the macOS compatibility layer and how to use it.

## Quick Start

### 1. Install Prerequisites

You'll need the following installed on your macOS system:

```bash
# Install Homebrew (if not already installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install pixi
brew install pixi
git clone https://github.com/open-energy-transition/earthpv.git && cd earthpv

# Install the environment
pixi install
```

### 2. Platform Support

The `pixi.toml` file has been updated to support macOS platforms:
- `osx-arm64` (Apple Silicon M1/M2/M3)
- `osx-64` (Intel Macs)
- `linux-64` (original Linux support)

Pixi will automatically detect your platform and install the appropriate packages.

## macOS Compatibility Layer

A compatibility layer (`scripts/macos_compat.sh`) provides cross-platform functions for common Linux commands that don't exist or behave differently on macOS.

### Usage

To use the compatibility layer in your shell scripts, source it at the beginning:

```bash
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/macos_compat.sh"
```

### Available Functions

#### File System
- **`stat_file_mtime <file>`** - Get file modification time in seconds since epoch
  - Linux: `stat -c %Y`
  - macOS: `stat -f %m`

- **`stat_file_size <file>`** - Get file size in bytes
  - Linux: `stat -c %s`
  - macOS: `stat -f %z`

- **`realpath <path>`** - Canonicalize a path (resolve symlinks)
  - Linux: `readlink -f`
  - macOS: Uses Python or a while loop

- **`free_gb <mount_point>`** - Get available disk space in GB
  - Linux: `df -BG --output=avail`
  - macOS: `df -BG` with parsed output

#### Process Management
- **`unit_active <unit_name>`** - Check if a service is running
  - Linux: `systemctl --user is-active --quiet`
  - macOS: `pgrep -f` or `launchctl list`

- **`start_unit <unit> <working_dir> <command>`** - Start a background service
  - Linux: `systemd-run --user`
  - macOS: `nohup` with background process

- **`stop_unit <unit>`** - Stop a service
  - Linux: `systemctl --user stop`
  - macOS: `pkill -f`

- **`list_units <pattern>`** - Check if any units matching pattern are active
  - Linux: `systemctl --user list-units`
  - macOS: `pgrep -f`

- **`n_units_active <pattern>`** - Count active units matching pattern
  - Linux: `systemctl --user list-units | wc -l`
  - macOS: `pgrep -f | wc -l`

## Running Scripts on macOS

### Updated Scripts

The following scripts have been updated to support macOS:

- `scripts/run_country_queue.sh` - Country processing queue

### Scripts That Need Manual Adjustment

Some scripts use Linux-specific commands and need to be updated or used with caution:

- `scripts/run_nigeria_chain.sh` - Uses `systemctl` and `stat -c`
- `scripts/download_vida.sh` - Uses `stat -c`
- `scripts/country_queue_status.sh` - Uses `stat -c`
- `scripts/gpu_yield_watch.sh` - Uses `systemctl`

To use these scripts on macOS, you can either:

1. **Source the compatibility layer** at the top of the script
2. **Manually replace** Linux commands with macOS equivalents

### Example: Updating a Script

Before:
```bash
#!/usr/bin/env bash
# Linux-specific
last=$(stat -c %Y "$file")
systemctl --user is-active --quiet myunit
```

After:
```bash
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/macos_compat.sh"

# Cross-platform
last=$(stat_file_mtime "$file")
unit_active myunit
```

## Known Limitations

### 1. Systemd vs Launchd

Linux uses `systemd` for service management, while macOS uses `launchd`. The compatibility layer provides basic functionality, but:

- **Resource limits** (MemoryMax, LimitNOFILE) are not enforced on macOS when using `nohup`
- **Service persistence** - macOS background processes may not survive logout
- **Logging** - Logs are written to files in `$HOME/.earthpv_units/` instead of journalctl

For production use on macOS, consider creating proper `launchd` plist files.

### 2. GPU Support

The ML environment uses CUDA (Linux) or Metal (macOS). PyTorch provides macOS wheels, but:

- GPU acceleration requires MPS (Metal Performance Shaders) on Apple Silicon
- Some PyTorch features may not be available on macOS
- Performance may differ from Linux

### 3. File System Differences

- **Case sensitivity**: macOS file system is case-insensitive by default
- **Symlinks**: macOS handles symlinks differently, especially in /tmp
- **Path lengths**: macOS has a lower maximum path length limit

### 4. Command-Line Tools

Some tools may have different names or options on macOS:

- `grep` - Use `ggrep` (GNU grep) if installed via Homebrew for consistent behavior
- `sed` - Use `gsed` (GNU sed) for consistent behavior
- `awk` - Use `gawk` (GNU awk) for consistent behavior

Install GNU tools with:
```bash
brew install grep sed awk
```

## Recommended Workflow

### For Development

1. Install Homebrew and pixi
2. Clone the repository
3. Run `pixi install`
4. Use the updated scripts with the compatibility layer

### For Production

1. Consider running in a Linux VM or Docker container for full compatibility
2. Use the macOS compatibility layer for scripts that must run natively
3. Monitor resource usage manually (no systemd resource limits on macOS)

## Troubleshooting

### "Command not found" Errors

If you see errors like `stat: illegal option -- c`, the script is using Linux-specific options. Either:

1. Update the script to use the compatibility layer
2. Install GNU coreutils: `brew install coreutils` and use `gstat` instead of `stat`

### Process Management Issues

If background processes aren't working correctly:

1. Check if the compatibility layer is sourced
2. Verify that `nohup` is available
3. Check for permission issues in `$HOME/.earthpv_units/`

### Disk Space Checks

The `free_gb` function parses `df` output differently on macOS. If you're seeing incorrect disk space values:

1. Verify the mount point exists
2. Check the output of `df -BG /` manually
3. Update the parsing logic in `macos_compat.sh` if needed

## Contributing macOS Support

If you improve macOS compatibility:

1. Test on both Intel and Apple Silicon Macs
2. Ensure backward compatibility with Linux
3. Document any macOS-specific requirements
4. Submit a pull request with your changes

## Additional Resources

- [Pixi Documentation](https://pixi.sh)
- [Homebrew Documentation](https://brew.sh)
- [macOS Command Line Tools](https://support.apple.com/guide/terminal/welcome/mac)
