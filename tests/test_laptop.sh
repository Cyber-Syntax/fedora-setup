#!/usr/bin/env bats
# tests/test_laptop.sh - Unit tests for laptop.sh functions

setup() {
  # Get the absolute path to the repository root
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

  # Create a temporary directory for test artifacts
  export BATS_TEST_TMPDIR=$(mktemp -d -p "${BATS_TMPDIR:-/tmp}" "laptop_test.XXXXXX")
  
  # Create mock filesystem structure
  export MOCK_ROOT="$BATS_TEST_TMPDIR/root"
  mkdir -p "$MOCK_ROOT/etc/tlp.d"
  mkdir -p "$MOCK_ROOT/etc/modprobe.d"
  mkdir -p "$MOCK_ROOT/etc/systemd/system"
  mkdir -p "$MOCK_ROOT/etc/X11/xorg.conf.d"
  mkdir -p "$MOCK_ROOT/etc/udev/rules.d"
  mkdir -p "$MOCK_ROOT/usr/lib/systemd/system/tlp.service.d"
  mkdir -p "$MOCK_ROOT/usr/lib/systemd/system/tlp-sleep.service.d"
  
  # Create mock config source directory
  mkdir -p "$BATS_TEST_TMPDIR/configs"
  echo "# Mock TLP config" > "$BATS_TEST_TMPDIR/configs/01-mytlp.conf"
  echo "# Mock touchpad config" > "$BATS_TEST_TMPDIR/configs/99-touchpad.conf"
  echo "# Mock Intel config" > "$BATS_TEST_TMPDIR/configs/20-intel.conf"
  echo "# Mock qtile rules" > "$BATS_TEST_TMPDIR/configs/99-qtile.rules"
  echo "# Mock backlight config" > "$BATS_TEST_TMPDIR/configs/99-backlight.conf"
  echo "# Mock thinkfan config" > "$BATS_TEST_TMPDIR/configs/thinkfan.conf"
  
  # Mock /etc/fedora-release
  echo "Fedora release 41 (Forty One)" > "$MOCK_ROOT/etc/fedora-release"
  
  # Create mock thinkfan.conf for backup test
  echo "# Original thinkfan config" > "$MOCK_ROOT/etc/thinkfan.conf"
  
  # Create mock systemd unit files for testing
  touch "$MOCK_ROOT/usr/lib/systemd/system/tlp.service"
  touch "$MOCK_ROOT/usr/lib/systemd/system/tlp-sleep.service"
  
  # Mock commands
  function hostnamectl() {
    echo "Mock hostnamectl: $*" >> "$BATS_TEST_TMPDIR/hostnamectl.log"
    return 0
  }
  export -f hostnamectl
  
  function systemctl() {
    if [[ "$1" == "list-unit-files" ]]; then
      if [[ "$SERVICES_EXIST" == "true" ]]; then
        echo "tuned.service                                disabled"
        echo "tuned-ppd.service                           disabled"
        echo "power-profile-daemon.service                disabled"
      fi
      return 0
    fi
    echo "Mock systemctl: $*" >> "$BATS_TEST_TMPDIR/systemctl.log"
    return 0
  }
  export -f systemctl
  
  function rpm() {
    if [[ "$1" == "-q" ]]; then
      if [[ "$RPM_PACKAGES_EXIST" == "true" ]]; then
        echo "package-$2-1.0-1.fc41.noarch"
        return 0
      fi
      return 1
    fi
    return 0
  }
  export -f rpm
  
  function sudo dnf() {
    echo "Mock sudo dnf: $*" >> "$BATS_TEST_TMPDIR/sudo dnf.log"
    return 0
  }
  export -f sudo dnf
  
  function modprobe() {
    echo "Mock modprobe: $*" >> "$BATS_TEST_TMPDIR/modprobe.log"
    return 0
  }
  export -f modprobe
  
  function cp() {
    # Intercept cp calls to config files and create the target files
    if [[ "$2" == "$MOCK_ROOT/etc/tlp.d/01-mytlp.conf" ]]; then
      echo "# TLP config copied from source" > "$MOCK_ROOT/etc/tlp.d/01-mytlp.conf"
    elif [[ "$2" == "$MOCK_ROOT/etc/thinkfan.conf" ]]; then
      echo "# Thinkfan config copied from source" > "$MOCK_ROOT/etc/thinkfan.conf"
    elif [[ "$2" == "$MOCK_ROOT/etc/X11/xorg.conf.d/99-touchpad.conf" ]]; then
      echo "# Touchpad config copied from source" > "$MOCK_ROOT/etc/X11/xorg.conf.d/99-touchpad.conf"
    elif [[ "$2" == "$MOCK_ROOT/etc/X11/xorg.conf.d/20-intel.conf" ]]; then
      echo "# Intel config copied from source" > "$MOCK_ROOT/etc/X11/xorg.conf.d/20-intel.conf"
    elif [[ "$2" == "$MOCK_ROOT/etc/udev/rules.d/99-qtile.rules" ]]; then
      echo "# Qtile rules copied from source" > "$MOCK_ROOT/etc/udev/rules.d/99-qtile.rules"
    elif [[ "$2" == "$MOCK_ROOT/etc/X11/xorg.conf.d/99-backlight.conf" ]]; then
      echo "# Backlight config copied from source" > "$MOCK_ROOT/etc/X11/xorg.conf.d/99-backlight.conf"
    else
      # For any other cp command, use the real cp
      command cp "$@"
    fi
    return 0
  }
  export -f cp
  
  function install() {
    echo "Mock install: $*" >> "$BATS_TEST_TMPDIR/install.log"
    # Create the target file for verification
    touch "${@: -1}"
    return 0
  }
  export -f install
  
  function udevadm() {
    echo "Mock udevadm: $*" >> "$BATS_TEST_TMPDIR/udevadm.log"
    return 0
  }
  export -f udevadm
  
  function sudo() {
    # Just execute the command without sudo for testing
    "$@"
    return $?
  }
  export -f sudo
  
  # Mock tee command
  function tee() {
    if [[ "$1" == "$MOCK_ROOT/etc/modprobe.d/thinkfan.conf" ]]; then
      echo "options thinkpad_acpi fan_control=1 experimental=1" > "$MOCK_ROOT/etc/modprobe.d/thinkfan.conf"
    elif [[ "$1" == "$MOCK_ROOT/etc/systemd/system/thinkfan-sleep-hack.service" ]]; then
      # Create the service file from stdin
      cat > "$MOCK_ROOT/etc/systemd/system/thinkfan-sleep-hack.service"
    fi
    return 0
  }
  export -f tee

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
    else
      # For all other grep calls, use command grep
      command grep "$@"
    fi
  }
  export -f grep
  
  function lspci() {
    if [[ "$NVIDIA_GPU" == "true" ]]; then
      echo "01:00.0 VGA compatible controller: NVIDIA Corporation GA104 [GeForce RTX 3070] (rev a1)"
    else
      echo "No NVIDIA GPU found"
    fi
    return 0
  }
  export -f lspci
  
  # Override environment variables to use mock paths
  export hostname_laptop="fedora-laptop"
  
  # Set logging directory for tests
  export LOG_DIR="$BATS_TEST_TMPDIR/logs"
  mkdir -p "$LOG_DIR"

  # Mock logging functions
  function log_info() { echo "[INFO] $1"; }
  function log_error() { echo "[ERROR] $1"; }
  function log_success() { echo "[SUCCESS] $1"; }
  function log_debug() { echo "[DEBUG] $1"; }
  function log_warn() { echo "[WARN] $1"; }
  
  export -f log_info log_error log_success log_debug log_warn
  
  # Path overrides for configs
  mkdir -p "$BATS_TEST_TMPDIR/configs"
  
  # Source the modules under test
  source "${REPO_ROOT}/src/logging.sh"
  
  # Override config paths for testing
  function modify_source() {
    local content="$(cat "$1")"
    # Replace absolute paths with mock paths
    content="${content//\/etc\/tlp.d/$MOCK_ROOT\/etc\/tlp.d}"
    content="${content//\/etc\/modprobe.d/$MOCK_ROOT\/etc\/modprobe.d}"
    content="${content//\/etc\/systemd\/system/$MOCK_ROOT\/etc\/systemd\/system}"
    content="${content//\/etc\/thinkfan.conf/$MOCK_ROOT\/etc\/thinkfan.conf}"
    content="${content//\/etc\/X11\/xorg.conf.d/$MOCK_ROOT\/etc\/X11\/xorg.conf.d}"
    content="${content//\/etc\/udev\/rules.d/$MOCK_ROOT\/etc\/udev\/rules.d}"
    content="${content//\/usr\/lib\/systemd\/system/$MOCK_ROOT\/usr\/lib\/systemd\/system}"
    content="${content//\/etc\/fedora-release/$MOCK_ROOT\/etc\/fedora-release}"
    echo "$content" > "$1.tmp"
    mv "$1.tmp" "$1"
  }
  
  # Create a modified version of the laptop.sh for testing
  cp "${REPO_ROOT}/src/laptop.sh" "$BATS_TEST_TMPDIR/laptop_test.sh"
  modify_source "$BATS_TEST_TMPDIR/laptop_test.sh"
  
  # Source the modified script
  source "$BATS_TEST_TMPDIR/laptop_test.sh"
}

teardown() {
  if [[ -d "$BATS_TEST_TMPDIR" ]]; then
    rm -rf "$BATS_TEST_TMPDIR"
  fi
}

@test "laptop_hostname_change sets hostname correctly" {
  run laptop_hostname_change
  
  [ "$status" -eq 0 ]
  
  # Verify hostnamectl was called with the correct hostname
  grep -q "set-hostname \"$hostname_laptop\"" "$BATS_TEST_TMPDIR/hostnamectl.log"
}

@test "tlp_setup configures TLP correctly" {
  # Setup for testing TLP with services and packages existing
  export SERVICES_EXIST=true
  export RPM_PACKAGES_EXIST=true
  
  # Set up config paths
  export config_src="$BATS_TEST_TMPDIR/configs/01-mytlp.conf"
  export config_dest="$MOCK_ROOT/etc/tlp.d/01-mytlp.conf"
  
  # Create the source config file
  echo "# Test TLP config" > "$config_src"
  
  run tlp_setup
  
  [ "$status" -eq 0 ]
  
  # Verify TLP config was copied
  [ -f "$config_dest" ]
  
  # Check if services were handled properly
  grep -q "systemctl: disable --now tuned" "$BATS_TEST_TMPDIR/systemctl.log"
  grep -q "systemctl: disable --now tuned-ppd" "$BATS_TEST_TMPDIR/systemctl.log"
  
  # Verify DNF remove was called
  grep -q "sudo dnf: remove -y tuned tuned-ppd" "$BATS_TEST_TMPDIR/sudo dnf.log"
  
  # Verify TLP services were enabled
  grep -q "systemctl: enable --now tlp" "$BATS_TEST_TMPDIR/systemctl.log"
  grep -q "systemctl: enable --now tlp-sleep" "$BATS_TEST_TMPDIR/systemctl.log"
  
  # Check rfkill masking
  grep -q "systemctl: mask systemd-rfkill.service" "$BATS_TEST_TMPDIR/systemctl.log"
  grep -q "systemctl: mask systemd-rfkill.socket" "$BATS_TEST_TMPDIR/systemctl.log"
}

@test "thinkfan_setup configures thinkfan correctly" {
  run thinkfan_setup
  
  [ "$status" -eq 0 ]
  
  # Verify thinkfan.conf was backed up and copied
  [ -f "$MOCK_ROOT/etc/thinkfan.conf.bak" ]
  [ -f "$MOCK_ROOT/etc/thinkfan.conf" ]
  
  # Check modprobe configuration
  [ -f "$MOCK_ROOT/etc/modprobe.d/thinkfan.conf" ]
  grep -q "options thinkpad_acpi fan_control=1 experimental=1" "$MOCK_ROOT/etc/modprobe.d/thinkfan.conf"
  
  # Verify modprobe calls
  grep -q "modprobe: -rv thinkpad_acpi" "$BATS_TEST_TMPDIR/modprobe.log"
  grep -q "modprobe: -v thinkpad_acpi" "$BATS_TEST_TMPDIR/modprobe.log"
  
  # Verify services were enabled
  grep -q "systemctl: enable --now thinkfan" "$BATS_TEST_TMPDIR/systemctl.log"
  grep -q "systemctl: enable thinkfan-sleep" "$BATS_TEST_TMPDIR/systemctl.log"
  grep -q "systemctl: enable thinkfan-wakeup" "$BATS_TEST_TMPDIR/systemctl.log"
  grep -q "systemctl: enable thinkfan-sleep-hack" "$BATS_TEST_TMPDIR/systemctl.log"
  
  # Verify the sleep hack service file was created
  [ -f "$MOCK_ROOT/etc/systemd/system/thinkfan-sleep-hack.service" ]
  grep -q "Description=Set fan to auto so BIOS can shut off fan during S2 sleep" "$MOCK_ROOT/etc/systemd/system/thinkfan-sleep-hack.service"
}

@test "xorg_setup_intel copies configuration files correctly" {
  # Set up config paths
  mkdir -p "$BATS_TEST_TMPDIR/configs"
  echo "# Test touchpad config" > "$BATS_TEST_TMPDIR/configs/99-touchpad.conf"
  echo "# Test Intel config" > "$BATS_TEST_TMPDIR/configs/20-intel.conf"
  
  # Export configs path for the command to find
  export configs="$BATS_TEST_TMPDIR/configs"
  
  run xorg_setup_intel
  
  [ "$status" -eq 0 ]
  
  # Verify configuration files were copied
  [ -f "$MOCK_ROOT/etc/X11/xorg.conf.d/99-touchpad.conf" ]
  [ -f "$MOCK_ROOT/etc/X11/xorg.conf.d/20-intel.conf" ]
}

@test "install_qtile_udev_rule sets up udev rules and reloads" {
  # Set up config paths
  mkdir -p "$BATS_TEST_TMPDIR/configs"
  echo "# Test qtile rules" > "$BATS_TEST_TMPDIR/configs/99-qtile.rules"
  echo "# Test backlight config" > "$BATS_TEST_TMPDIR/configs/99-backlight.conf"
  
  # Export configs path for the command to find
  export configs="$BATS_TEST_TMPDIR/configs"
  
  run install_qtile_udev_rule
  
  [ "$status" -eq 0 ]
  
  # Verify files were copied
  [ -f "$MOCK_ROOT/etc/udev/rules.d/99-qtile.rules" ]
  [ -f "$MOCK_ROOT/etc/X11/xorg.conf.d/99-backlight.conf" ]
  
  # Verify udev rules were reloaded
  grep -q "udevadm: control --reload-rules" "$BATS_TEST_TMPDIR/udevadm.log"
  grep -q "udevadm: trigger" "$BATS_TEST_TMPDIR/udevadm.log"
}
