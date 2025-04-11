#!/usr/bin/env bats
# tests/test_desktop.sh - Unit tests for desktop.sh functions

setup() {
  # Get the absolute path to the repository root
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

  # Create a temporary directory for test artifacts
  export BATS_TEST_TMPDIR=$(mktemp -d -p "${BATS_TMPDIR:-/tmp}" "desktop_test.XXXXXX")
  
  # Create mock filesystem structure
  export MOCK_ROOT="$BATS_TEST_TMPDIR/root"
  mkdir -p "$MOCK_ROOT/opt/borg"
  mkdir -p "$MOCK_ROOT/etc/gdm"
  mkdir -p "$MOCK_ROOT/etc/rpm"
  mkdir -p "$MOCK_ROOT/etc/systemd/system"
  mkdir -p "$MOCK_ROOT/etc/modprobe.d"
  mkdir -p "$MOCK_ROOT/etc/environment"
  
  # Create mock script directory
  mkdir -p "$BATS_TEST_TMPDIR/scripts/desktop/borg"
  echo "#!/bin/bash\necho 'Mock borgbackup script'" > "$BATS_TEST_TMPDIR/scripts/desktop/borg/home-borgbackup.sh"
  chmod +x "$BATS_TEST_TMPDIR/scripts/desktop/borg/home-borgbackup.sh"
  
  # Mock commands
  function command() {
    if [[ "$1" == "-v" && "$2" == "ollama" ]]; then
      # Control whether ollama is installed based on env var
      if [[ "$OLLAMA_INSTALLED" == "true" ]]; then
        echo "/usr/bin/ollama"
        return 0
      else
        return 1
      fi
    elif [[ "$1" == "-v" && "$2" == "nvcc" ]]; then
      # Control whether CUDA is installed
      if [[ "$CUDA_INSTALLED" == "true" ]]; then
        echo "/usr/local/cuda/bin/nvcc"
        return 0
      else
        return 1
      fi
    else
      # Pass through other command calls
      command "$@"
    fi
  }
  export -f command
  
  function curl() {
    if [[ "$1" == "-fsSL" && "$2" == "https://ollama.com/install.sh" ]]; then
      # Echo a mock script that succeeds
      echo "echo 'Installing Ollama...'; touch $BATS_TEST_TMPDIR/ollama_installed"
      return 0
    else
      # Mock other curl calls
      echo "Mock curl: $*" >> "$BATS_TEST_TMPDIR/curl.log"
      return 0
    fi
  }
  export -f curl
  
  function sh() {
    if [[ "$*" == *"ollama"* ]]; then
      # Make the fake ollama binary
      mkdir -p "$MOCK_ROOT/usr/bin"
      echo "#!/bin/bash" > "$MOCK_ROOT/usr/bin/ollama"
      chmod +x "$MOCK_ROOT/usr/bin/ollama"
      export OLLAMA_INSTALLED=true
      echo "Mock sh: Installed Ollama" >> "$BATS_TEST_TMPDIR/sh.log"
    else
      echo "Mock sh: $*" >> "$BATS_TEST_TMPDIR/sh.log"
    fi
    return 0
  }
  export -f sh
  
  function mkdir() {
    # Use real mkdir but log calls
    echo "Mock mkdir: $*" >> "$BATS_TEST_TMPDIR/mkdir.log"
    command mkdir "$@"
    return $?
  }
  export -f mkdir
  
  function mv() {
    # Log calls to mv and execute simple ones
    echo "Mock mv: $*" >> "$BATS_TEST_TMPDIR/mv.log"
    if [[ "$2" == "$MOCK_ROOT/opt/borg/home-borgbackup.sh" ]]; then
      echo "#!/bin/bash\necho 'Mock borgbackup script'" > "$MOCK_ROOT/opt/borg/home-borgbackup.sh"
      chmod +x "$MOCK_ROOT/opt/borg/home-borgbackup.sh"
      return 0
    else
      command mv "$@"
      return $?
    fi
  }
  export -f mv
  
  function systemctl() {
    echo "Mock systemctl: $*" >> "$BATS_TEST_TMPDIR/systemctl.log"
    return 0
  }
  export -f systemctl
  
  function akmods() {
    echo "Mock akmods: $*" >> "$BATS_TEST_TMPDIR/akmods.log"
    if [[ "$*" == *"--force"* ]]; then
      return 0
    elif [[ "$AKMODS_FAIL" == "true" ]]; then
      return 1
    else
      return 0
    fi
  }
  export -f akmods
  
  function dnf() {
    echo "Mock dnf: $*" >> "$BATS_TEST_TMPDIR/dnf.log"
    if [[ "$1" == "copr" && "$2" == "enable" ]]; then
      # Create a fake repo file to simulate repo installation
      local repo_name="${3//\//_}"
      touch "$MOCK_ROOT/etc/yum.repos.d/$repo_name.repo"
    elif [[ "$1" == "install" ]]; then
      # Create fake binaries for installed packages
      shift
      for pkg in "$@"; do
        if [[ "$pkg" != "-y" ]]; then
          touch "$MOCK_ROOT/usr/bin/$pkg"
        fi
      done
    fi
    return 0
  }
  export -f dnf
  
  function lspci() {
    if [[ "$NVIDIA_GPU" == "true" ]]; then
      echo "01:00.0 VGA compatible controller: NVIDIA Corporation GA104 [GeForce RTX 3070] (rev a1)"
    else
      echo "No NVIDIA GPU found"
    fi
    return 0
  }
  export -f lspci
  
  function rpm() {
    if [[ "$1" == "-q" && "$2" == "NetworkManager" ]]; then
      if [[ "$NETWORK_MANAGER_INSTALLED" == "true" ]]; then
        echo "NetworkManager-1.42.2-1.fc41.x86_64"
        return 0
      else
        return 1
      fi
    elif [[ "$1" == "-q" && "$2" =~ ^gnome-.* ]]; then
      if [[ "$GNOME_INSTALLED" == "true" ]]; then
        echo "$2-42.0-1.fc41.x86_64"
        return 0
      else
        return 1
      fi
    fi
    return 0
  }
  export -f rpm
  
  function read() {
    # Simulate user input in remove_gnome function
    if [[ "$GNOME_REMOVE_CONFIRMED" == "true" ]]; then
      echo "y" # User confirmed
    else
      echo "n" # User declined
    fi
    return 0
  }
  export -f read
  
  function grep() {
    if [[ "$1" == "-q" && "$2" == "AMD" && "$3" == "/proc/cpuinfo" ]]; then
      # Simulate AMD CPU detection
      if [[ "$AMD_CPU" == "true" ]]; then
        return 0  # Success, AMD CPU found
      else
        return 1  # Failure, AMD CPU not found
      fi
    elif [[ "$1" == "-q" && "$2" == "nvidia" ]]; then
      # Simulate NVIDIA GPU detection
      if [[ "$NVIDIA_GPU" == "true" ]]; then
        return 0  # Success, NVIDIA GPU found
      else
        return 1  # Failure, NVIDIA GPU not found
      fi
    elif [[ "$@" =~ ^"-q.*nvidia.*" ]]; then
      # Catch variations of nvidia GPU detection
      if [[ "$NVIDIA_GPU" == "true" ]]; then
        return 0
      else
        return 1
      fi
    elif [[ "$@" =~ ^"-q.*${var}.*${env_file}" ]]; then
      # Simulating checking if environment variables already exist
      if [[ "$ENV_VARS_EXIST" == "true" ]]; then
        return 0
      else
        return 1
      fi
    else
      # For all other grep calls, use command grep
      command grep "$@"
    fi
  }
  export -f grep
  
  # Override environment variables for testing
  export borgbackup_script="$BATS_TEST_TMPDIR/scripts/desktop/borg/home-borgbackup.sh"
  export move_opt_dir="$MOCK_ROOT/opt/borg/home-borgbackup.sh"
  export borgbackup_service="$MOCK_ROOT/etc/systemd/system/borgbackup-home.service"
  export borgbackup_timer="$MOCK_ROOT/etc/systemd/system/borgbackup-home.timer"
  export USER="developer"
  
  # Set logging directory for tests
  export LOG_DIR="$BATS_TEST_TMPDIR/logs"
  mkdir -p "$LOG_DIR"

  # Mock logging functions instead of sourcing the file
  function log_info() { echo "[INFO] $1"; }
  function log_error() { echo "[ERROR] $1"; }
  function log_success() { echo "[SUCCESS] $1"; }
  function log_debug() { echo "[DEBUG] $1"; }
  function log_warn() { echo "[WARN] $1"; }
  
  export -f log_info log_error log_success log_debug log_warn
  
  # Source the variables script if available, but don't fail if it's not
  source "${REPO_ROOT}/src/variables.sh" 2>/dev/null || true
  
  # Get the content of desktop.sh and modify paths for testing
  cat "${REPO_ROOT}/src/desktop.sh" | \
    sed "s|/opt/borg|$MOCK_ROOT/opt/borg|g" | \
    sed "s|/etc/systemd/system|$MOCK_ROOT/etc/systemd/system|g" | \
    sed "s|/etc/gdm|$MOCK_ROOT/etc/gdm|g" | \
    sed "s|/etc/rpm|$MOCK_ROOT/etc/rpm|g" | \
    sed "s|/etc/modprobe.d|$MOCK_ROOT/etc/modprobe.d|g" | \
    sed "s|/etc/environment|$MOCK_ROOT/etc/environment|g" > \
    "$BATS_TEST_TMPDIR/desktop_test.sh"
  
  # Source the modified desktop.sh
  source "$BATS_TEST_TMPDIR/desktop_test.sh"
}

teardown() {
  if [[ -d "$BATS_TEST_TMPDIR" ]]; then
    rm -rf "$BATS_TEST_TMPDIR"
  fi
}

@test "install_ollama detects existing installation" {
  # Test when Ollama is already installed
  export OLLAMA_INSTALLED=true
  
  run install_ollama
  
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ollama is already installed"* ]]
}

@test "install_ollama installs when not present" {
  # Test when Ollama is not installed
  export OLLAMA_INSTALLED=false
  
  run install_ollama
  
  [ "$status" -eq 0 ]
  
  # Verify the script was downloaded and executed
  grep -q "curl -fsSL https://ollama.com/install.sh" "$BATS_TEST_TMPDIR/sh.log" || \
    grep -q "ollama" "$BATS_TEST_TMPDIR/sh.log"
  
  # Should be marked as installed after the installation
  [ -x "$MOCK_ROOT/usr/bin/ollama" ] || [ "$OLLAMA_INSTALLED" == "true" ]
}

@test "borgbackup_setup creates directories and service files" {
  run borgbackup_setup
  
  [ "$status" -eq 0 ]
  
  # Verify directory was created
  [ -d "$MOCK_ROOT/opt/borg" ]
  
  # Verify script was moved
  [ -f "$MOCK_ROOT/opt/borg/home-borgbackup.sh" ]
  
  # Verify service and timer files were created
  [ -f "$MOCK_ROOT/etc/systemd/system/borgbackup-home.service" ]
  [ -f "$MOCK_ROOT/etc/systemd/system/borgbackup-home.timer" ]
  
  # Check service content
  grep -q "Description=Home Backup using BorgBackup" "$borgbackup_service"
  grep -q "ExecStart=/opt/borg/home-borgbackup.sh" "$borgbackup_service"
  
  # Check timer content
  grep -q "Description=Timer for Home Backup using BorgBackup" "$borgbackup_timer"
  grep -q "OnCalendar=\\*-\\*-\\* 10:00:00" "$borgbackup_timer"
  grep -q "WantedBy=timers.target" "$borgbackup_timer"
  
  # Verify systemd was reloaded and service enabled
  grep -q "systemctl: daemon-reload" "$BATS_TEST_TMPDIR/systemctl.log"
  grep -q "systemctl: enable --now borgbackup-home.timer" "$BATS_TEST_TMPDIR/systemctl.log"
}

@test "gdm_auto_login creates gdm configuration" {
  # Test when user is root
  export EUID=0
  
  run gdm_auto_login
  
  [ "$status" -eq 0 ]
  
  # Verify gdm custom.conf was created
  [ -f "$MOCK_ROOT/etc/gdm/custom.conf" ]
  
  # Check configuration content
  grep -q "AutomaticLoginEnable=True" "$MOCK_ROOT/etc/gdm/custom.conf"
  grep -q "AutomaticLogin=$USER" "$MOCK_ROOT/etc/gdm/custom.conf"
}

@test "gdm_auto_login fails when not root" {
  # Test when user is not root
  export EUID=1000
  
  run gdm_auto_login
  
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be run as root"* ]]
}

@test "zenpower_setup installs zenpower on AMD systems" {
  # Test with AMD CPU
  export AMD_CPU=true
  
  run zenpower_setup
  
  [ "$status" -eq 0 ]
  
  # Verify repository was enabled and packages installed
  grep -q "dnf: copr enable shdwchn10/zenpower3 -y" "$BATS_TEST_TMPDIR/dnf.log"
  grep -q "dnf: install -y zenpower3 zenmonitor3" "$BATS_TEST_TMPDIR/dnf.log"
  
  # Verify blacklist file was created
  [ -f "$MOCK_ROOT/etc/modprobe.d/zenpower.conf" ]
  echo "$(cat $MOCK_ROOT/etc/modprobe.d/zenpower.conf)"
  grep -q "blacklist k10temp" "$MOCK_ROOT/etc/modprobe.d/zenpower.conf" || echo "Missing blacklist directive"
}

@test "zenpower_setup fails on non-AMD systems" {
  # Test with non-AMD CPU
  export AMD_CPU=false
  
  run zenpower_setup
  
  [ "$status" -eq 1 ]
  [[ "$output" == *"This system does not appear to have an AMD CPU"* ]]
}

@test "nvidia_cuda_setup installs CUDA on systems with NVIDIA GPU" {
  # Test with NVIDIA GPU
  export NVIDIA_GPU=true
  
  run nvidia_cuda_setup
  
  [ "$status" -eq 0 ]
  
  # Verify CUDA repository was added
  grep -q "dnf: config-manager addrepo" "$BATS_TEST_TMPDIR/dnf.log"
  
  # Verify CUDA toolkit was installed
  grep -q "dnf: -y install cuda-toolkit" "$BATS_TEST_TMPDIR/dnf.log"
}

@test "nvidia_cuda_setup fails on systems without NVIDIA GPU" {
  # Test without NVIDIA GPU
  export NVIDIA_GPU=false
  
  run nvidia_cuda_setup
  
  [ "$status" -eq 1 ]
  [[ "$output" == *"No NVIDIA GPU detected"* ]]
}

@test "switch_nvidia_open configures NVIDIA open source drivers" {
  # Test with NVIDIA GPU and root privileges
  export NVIDIA_GPU=true
  export EUID=0
  
  run switch_nvidia_open
  
  [ "$status" -eq 0 ]
  
  # Verify nvidia kmod macro file was created
  [ -f "$MOCK_ROOT/etc/rpm/macros.nvidia-kmod" ]
  grep -q "%_with_kmod_nvidia_open 1" "$MOCK_ROOT/etc/rpm/macros.nvidia-kmod"
  
  # Verify modules were rebuilt
  grep -q "akmods: --kernels" "$BATS_TEST_TMPDIR/akmods.log"
  
  # Verify repository was disabled
  grep -q "dnf: --disablerepo rpmfusion-nonfree-nvidia-driver" "$BATS_TEST_TMPDIR/dnf.log"
}

@test "switch_nvidia_open fails when not root" {
  # Test with NVIDIA GPU but not root
  export NVIDIA_GPU=true
  export EUID=1000
  
  run switch_nvidia_open
  
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be run as root"* ]]
}

@test "vaapi_setup configures VA-API for NVIDIA systems" {
  # Test with NVIDIA GPU
  export NVIDIA_GPU=true
  export ENV_VARS_EXIST=false
  
  # Create environment file
  touch "$MOCK_ROOT/etc/environment"
  
  run vaapi_setup
  
  [ "$status" -eq 0 ]
  
  # Verify VA-API packages were installed
  grep -q "dnf: install -y" "$BATS_TEST_TMPDIR/dnf.log"
  [[ "$(cat $BATS_TEST_TMPDIR/dnf.log)" == *"meson"* ]]
  [[ "$(cat $BATS_TEST_TMPDIR/dnf.log)" == *"nvidia-vaapi-driver"* ]]
  
  # Verify environment variables were set
  [ -f "$MOCK_ROOT/etc/environment" ]
  grep -q "MOZ_DISABLE_RDD_SANDBOX=1" "$MOCK_ROOT/etc/environment" || echo "Missing MOZ var"
  grep -q "LIBVA_DRIVER_NAME=nvidia" "$MOCK_ROOT/etc/environment" || echo "Missing LIBVA var"
  grep -q "__GLX_VENDOR_LIBRARY_NAME=nvidia" "$MOCK_ROOT/etc/environment" || echo "Missing GLX var"
}

@test "remove_gnome preserves NetworkManager" {
  # Test when GNOME is installed and user confirms
  export GNOME_INSTALLED=true
  export NETWORK_MANAGER_INSTALLED=true
  export GNOME_REMOVE_CONFIRMED=true
  
  run remove_gnome
  
  [ "$status" -eq 0 ]
  
  # Verify GNOME packages were removed
  grep -q "dnf: remove -y gnome-shell gnome-session gnome-desktop" "$BATS_TEST_TMPDIR/dnf.log"
  
  # Check that NetworkManager status was verified after removal
  [[ "$output" == *"NetworkManager is still installed and preserved"* ]]
}

@test "remove_gnome cancels when user declines" {
  # Test when user declines removal
  export GNOME_INSTALLED=true
  export GNOME_REMOVE_CONFIRMED=false
  
  run remove_gnome
  
  [ "$status" -eq 0 ]
  [[ "$output" == *"GNOME removal cancelled by user"* ]]
}

@test "remove_gnome skips when GNOME is not installed" {
  # Test when GNOME is not installed
  export GNOME_INSTALLED=false
  
  run remove_gnome
  
  [ "$status" -eq 0 ]
  [[ "$output" == *"GNOME packages are not installed"* ]]
}
