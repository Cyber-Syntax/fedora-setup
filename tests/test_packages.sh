#!/usr/bin/env bats
# tests/test_packages.sh - Unit tests for packages.sh functions

setup() {
  # Get the absolute path to the repository root
  # Use BATS_TEST_DIRNAME which is more reliable than BATS_TEST_FILENAME
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  
  # Create a temporary directory for test artifacts
  export BATS_TEST_TMPDIR=$(mktemp -d -p "${BATS_TMPDIR:-/tmp}" "packages_test.XXXXXX")
  
  # Create mock filesystem structure
  export MOCK_ROOT="$BATS_TEST_TMPDIR/root"
  mkdir -p "$MOCK_ROOT/usr/bin"
  
  # Mock commands
  function dnf() {
    echo "Mock dnf: $*" >> "$BATS_TEST_TMPDIR/dnf.log"
    
    # For successful installation, create fake binaries
    if [[ "$1" == "install" ]]; then
      shift # remove 'install'
      if [[ "$1" == "-y" ]]; then
        shift # remove '-y'
      fi
      
      # Create a dummy file for each "installed" package
      for pkg in "$@"; do
        # Skip array variables or quotes
        if [[ "$pkg" != '"${qtile_packages[@]}"' && "$pkg" != '${qtile_packages[@]}' && 
              "$pkg" != '"${CORE_PACKAGES[@]}"' && "$pkg" != '${CORE_PACKAGES[@]}' && 
              "$pkg" != '"${DESKTOP_PACKAGES[@]}"' && "$pkg" != '${DESKTOP_PACKAGES[@]}' && 
              "$pkg" != '"${LAPTOP_PACKAGES[@]}"' && "$pkg" != '${LAPTOP_PACKAGES[@]}' ]]; then
          touch "$MOCK_ROOT/usr/bin/$pkg"
        fi
      done
      
      # Return success or failure based on DNF_FAILS env var
      if [[ "$DNF_FAILS" == "true" ]]; then
        return 1
      else
        return 0
      fi
    fi
    
    # Handle dnf update
    if [[ "$1" == "update" ]]; then
      if [[ "$DNF_FAILS" == "true" ]]; then
        return 1
      else
        return 0
      fi
    fi
    
    return 0
  }
  export -f dnf
  
  function flatpak() {
    echo "Mock flatpak: $*" >> "$BATS_TEST_TMPDIR/flatpak.log"
    
    # Simulate success or failure based on env var
    if [[ "$FLATPAK_FAILS" == "true" ]]; then
      return 1
    else
      return 0
    fi
  }
  export -f flatpak
  
  # Set logging directory for tests
  export LOG_DIR="$BATS_TEST_TMPDIR/logs"
  mkdir -p "$LOG_DIR"

  # Mock logging functions instead of sourcing the file
  # This prevents the error when logging.sh is not found
  function log_info() { echo "[INFO] $1"; }
  function log_error() { echo "[ERROR] $1"; }
  function log_success() { echo "[SUCCESS] $1"; }
  function log_debug() { echo "[DEBUG] $1"; }
  function log_warn() { echo "[WARN] $1"; }
  
  export -f log_info log_error log_success log_debug log_warn

  # Source the packages script directly with absolute path
  if [[ -f "${REPO_ROOT}/src/packages.sh" ]]; then
    # Use a modified version of packages.sh that doesn't try to source logging.sh
    sed '/source src\/logging.sh/d' "${REPO_ROOT}/src/packages.sh" > "$BATS_TEST_TMPDIR/packages.sh.tmp"
    source "$BATS_TEST_TMPDIR/packages.sh.tmp"
  else
    echo "ERROR: packages.sh not found at ${REPO_ROOT}/src/packages.sh"
    return 1
  fi
  
  # Create test package arrays if not defined in packages.sh
  if [[ -z "${CORE_PACKAGES[@]}" ]]; then
    CORE_PACKAGES=("zsh" "vim" "git" "htop" "btop")
  fi
  
  if [[ -z "${DESKTOP_PACKAGES[@]}" ]]; then
    DESKTOP_PACKAGES=("virt-manager" "libvirt" "nvidia-open")
  fi
  
  if [[ -z "${LAPTOP_PACKAGES[@]}" ]]; then
    LAPTOP_PACKAGES=("powertop" "tlp" "tlp-rdw")
  fi
  
  if [[ -z "${FLATPAK_PACKAGES[@]}" ]]; then
    FLATPAK_PACKAGES=("org.signal.Signal" "com.spotify.Client")
  fi
}

teardown() {
  if [[ -d "$BATS_TEST_TMPDIR" ]]; then
    rm -rf "$BATS_TEST_TMPDIR"
  fi
}

@test "install_qtile_packages installs required packages" {
  run install_qtile_packages
  
  [ "$status" -eq 0 ]
  
  # Verify dnf install was called
  [ -f "$BATS_TEST_TMPDIR/dnf.log" ]
  grep -q "Mock dnf: install -y" "$BATS_TEST_TMPDIR/dnf.log"
  
  # Check success message was logged
  [[ "$output" == *"Qtile packages installation completed"* ]]
}

@test "install_qtile_packages handles errors gracefully" {
  # Set DNF to fail
  export DNF_FAILS=true
  
  run install_qtile_packages
  
  # Function should return failure
  [ "$status" -eq 1 ]
  
  # Error message should be logged
  [[ "$output" == *"Failed to install Qtile packages"* ]]
}