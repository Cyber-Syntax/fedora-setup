#!/usr/bin/env bash
# tests/test_helper.bash - Common functions for BATS tests

# Get the repository root based on the test directory
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Create standardized mock directory structure
setup_mock_filesystem() {
  local temp_dir="$1"
  
  # Create common directory structure
  mkdir -p "$temp_dir/root/etc"
  mkdir -p "$temp_dir/root/etc/dnf"
  mkdir -p "$temp_dir/root/etc/yum.repos.d"
  mkdir -p "$temp_dir/root/etc/systemd/system"
  mkdir -p "$temp_dir/root/etc/X11/xorg.conf.d"
  mkdir -p "$temp_dir/root/etc/udev/rules.d"
  mkdir -p "$temp_dir/root/etc/modprobe.d"
  mkdir -p "$temp_dir/root/etc/sudoers.d"
  mkdir -p "$temp_dir/root/etc/sysctl.d"
  mkdir -p "$temp_dir/root/opt"
  mkdir -p "$temp_dir/root/usr/bin"
  mkdir -p "$temp_dir/root/usr/share/applications"
  mkdir -p "$temp_dir/home/.local/share/applications"
  mkdir -p "$temp_dir/home/.mozilla/firefox/default"
  
  # Create common config files
  touch "$temp_dir/root/etc/dnf/dnf.conf"
  touch "$temp_dir/root/etc/fedora-release"
  echo "Fedora release 41 (Forty One)" > "$temp_dir/root/etc/fedora-release"
  
  # Create logs directory
  mkdir -p "$temp_dir/logs"
}

# Create a mock command that logs its calls and parameters
create_mock_command() {
  local command="$1"
  local mock_dir="$2"
  local return_val="${3:-0}"  # Default return value is 0 (success)
  
  # Create the mock command function
  eval "function $command() {
    echo \"Mock $command: \$*\" >> \"$mock_dir/$command.log\"
    return $return_val
  }
  export -f $command"
}

# Create a mock DNF command with common behaviors
mock_dnf() {
  local log_file="$1"
  
  function dnf() {
    local cmd="$1"
    echo "Mock dnf: $*" >> "$log_file"
    
    case "$cmd" in
      install)
        if [[ "$DNF_FAILS" == "true" ]]; then
          return 1
        else
          # Simulate successful installation
          shift # Remove 'install'
          if [[ "$1" == "-y" ]]; then
            shift # Remove '-y'
          fi
          return 0
        fi
        ;;
      update|upgrade)
        if [[ "$DNF_FAILS" == "true" ]]; then
          return 1
        else
          return 0
        fi
        ;;
      repolist)
        if [[ "$RPM_FUSION_ENABLED" == "true" ]]; then
          echo "rpmfusion-free        RPM Fusion for Fedora 41 - Free     enabled"
          echo "rpmfusion-nonfree     RPM Fusion for Fedora 41 - Nonfree  enabled"
        fi
        return 0
        ;;
      *)
        return 0
        ;;
    esac
  }
  export -f dnf
}

# Create a mock systemctl command with common behaviors
mock_systemctl() {
  local log_file="$1"
  
  function systemctl() {
    echo "Mock systemctl: $*" >> "$log_file"
    
    if [[ "$1" == "list-unit-files" ]]; then
      if [[ "$SERVICES_EXIST" == "true" ]]; then
        echo "tuned.service                                disabled"
        echo "power-profile-daemon.service                 disabled"
      fi
      return 0
    fi
    
    return 0
  }
  export -f systemctl
}

# Override file operations to work safely in mock filesystem
mock_file_operations() {
  local mock_root="$1"
  
  function mkdir() {
    echo "Mock mkdir: $*" >> "$BATS_TEST_TMPDIR/mkdir.log"
    command mkdir "$@"
    return $?
  }
  export -f mkdir
  
  function cp() {
    echo "Mock cp: $*" >> "$BATS_TEST_TMPDIR/cp.log"
    command cp "$@"
    return $?
  }
  export -f cp
  
  function mv() {
    echo "Mock mv: $*" >> "$BATS_TEST_TMPDIR/mv.log"
    command mv "$@"
    return $?
  }
  export -f mv
  
  function chmod() {
    echo "Mock chmod: $*" >> "$BATS_TEST_TMPDIR/chmod.log"
    command chmod "$@"
    return $?
  }
  export -f chmod
}

# Check if the current user is root or using sudo
is_root() {
  if [[ $EUID -eq 0 ]]; then
    return 0  # True, is root
  else
    return 1  # False, not root
  fi
}

# Clean up test artifacts
cleanup_test_dir() {
  if [[ -d "$1" ]]; then
    rm -rf "$1"
  fi
}

# Add mock logging functions that can be used in tests
mock_logging_functions() {
  function log_info() { echo "[INFO] $1"; }
  function log_error() { echo "[ERROR] $1"; }
  function log_success() { echo "[SUCCESS] $1"; }
  function log_debug() { echo "[DEBUG] $1"; }
  function log_warn() { echo "[WARN] $1"; }
  
  export -f log_info log_error log_success log_debug log_warn
}
