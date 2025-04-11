#!/usr/bin/env bats
# tests/test_setup.sh - Integration tests for main setup.sh script

load test_helper

setup() {
  # Get absolute path to repository root
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  
  # Create a temporary directory for test artifacts
  export BATS_TEST_TMPDIR=$(mktemp -d -p "${BATS_TMPDIR:-/tmp}" "setup_test.XXXXXX")
  
  # Set up mock filesystem structure
  setup_mock_filesystem "$BATS_TEST_TMPDIR"
  export MOCK_ROOT="$BATS_TEST_TMPDIR/root"
  
  # Create log directory for the test
  export LOG_DIR="$BATS_TEST_TMPDIR/logs"
  mkdir -p "$LOG_DIR"
  
  # Set up mock commands
  mock_dnf "$BATS_TEST_TMPDIR/dnf.log"
  mock_systemctl "$BATS_TEST_TMPDIR/systemctl.log"
  
  # Mock additional commands used by setup.sh
  function hostname() {
    if [[ "$MOCK_HOSTNAME" == "laptop" ]]; then
      echo "fedora-laptop"
    else
      echo "fedora"  # Default to desktop
    fi
    return 0
  }
  export -f hostname
  
  function id() {
    if [[ "$1" == "$USER" ]]; then
      return 0  # Success - user exists
    else
      return 1  # Failure - user doesn't exist
    fi
  }
  export -f id
  
  function grep() {
    if [[ "$1" == "-q" && "$2" == "^GRUB_TIMEOUT=" ]]; then
      # Simulate finding GRUB_TIMEOUT in boot file
      return 0
    elif [[ "$1" == "-q" && "$2" == "^GRUB_CMDLINE_LINUX=" ]]; then
      # Simulate finding GRUB_CMDLINE_LINUX in boot file
      return 0
    elif [[ "$@" =~ "nvidia" ]]; then
      if [[ "$NVIDIA_GPU" == "true" ]]; then
        return 0
      else
        return 1
      fi
    else
      command grep "$@"
    fi
  }
  export -f grep
  
  # Mock sed and grub2-mkconfig
  create_mock_command "sed" "$BATS_TEST_TMPDIR"
  create_mock_command "grub2-mkconfig" "$BATS_TEST_TMPDIR"
  
  # Set up environment variables
  export EUID=0  # Mock as running as root
  export USER="developer"
  export boot_file="$MOCK_ROOT/etc/default/grub"
  export tcp_bbr="$MOCK_ROOT/etc/sysctl.d/99-tcp-bbr.conf"
  export sudoers_file="$MOCK_ROOT/etc/sudoers.d/custom-conf"
  export hostname_desktop="fedora"
  export hostname_laptop="fedora-laptop"
  
  # Create mock grub file
  echo "GRUB_TIMEOUT=5" > "$boot_file"
  echo "GRUB_CMDLINE_LINUX=\"rhgb quiet\"" >> "$boot_file"
  
  # Create modified setup.sh with paths pointing to mock filesystem
  cat "${REPO_ROOT}/setup.sh" | \
    sed "s|/etc/default/grub|$MOCK_ROOT/etc/default/grub|g" | \
    sed "s|/etc/sysctl.d/99-tcp-bbr.conf|$MOCK_ROOT/etc/sysctl.d/99-tcp-bbr.conf|g" | \
    sed "s|/etc/sudoers.d/custom-conf|$MOCK_ROOT/etc/sudoers.d/custom-conf|g" > \
    "$BATS_TEST_TMPDIR/setup_test.sh"
  
  chmod +x "$BATS_TEST_TMPDIR/setup_test.sh"
  
  # Mock logging functions
  mock_logging_functions
}

teardown() {
  cleanup_test_dir "$BATS_TEST_TMPDIR"
}

# Test functions that handle parsing command line arguments
@test "setup.sh -h displays help message" {
  # Source main script with modified paths
  source "$BATS_TEST_TMPDIR/setup_test.sh"
  
  run usage
  
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"Options:"* ]]
  [[ "$output" == *"-h    Display this help message"* ]]
}

@test "setup.sh detects system type correctly for desktop" {
  # Source main script with modified paths
  source "$BATS_TEST_TMPDIR/setup_test.sh"
  
  export MOCK_HOSTNAME="desktop"
  
  run detect_system_type
  
  [ "$status" -eq 0 ]
  [ "$output" = "desktop" ]
}

@test "setup.sh detects system type correctly for laptop" {
  # Source main script with modified paths
  source "$BATS_TEST_TMPDIR/setup_test.sh"
  
  export MOCK_HOSTNAME="laptop"
  
  run detect_system_type
  
  [ "$status" -eq 0 ]
  [ "$output" = "laptop" ]
}

@test "setup.sh check_root works correctly" {
  # Source main script with modified paths
  source "$BATS_TEST_TMPDIR/setup_test.sh"
  
  # Test with root
  export EUID=0
  
  run check_root
  
  [ "$status" -eq 0 ]
  
  # Test without root
  export EUID=1000
  
  run check_root
  
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be run as root"* ]]
}

@test "setup.sh warning when USER variable is not configured" {
  # Source main script with modified paths but modify it to trigger the warning
  cat "${REPO_ROOT}/setup.sh" | \
    sed "s|id \"\$USER\" \&>/dev/null|id \"non_existent_user\" \&>/dev/null|g" \
    > "$BATS_TEST_TMPDIR/setup_warning.sh"
  
  chmod +x "$BATS_TEST_TMPDIR/setup_warning.sh"
  
  # Run the script with warning flow
  run "$BATS_TEST_TMPDIR/setup_warning.sh"
  
  [ "$status" -eq 1 ]
  [[ "$output" == *"forget to change variables"* ]]
}

@test "setup.sh grub_timeout modifies boot configuration" {
  # Source main script with modified paths
  source "$BATS_TEST_TMPDIR/setup_test.sh"
  
  run grub_timeout
  
  [ "$status" -eq 0 ]
  
  # Verify sed was called to update the grub timeout
  grep -q "sed: 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/'" "$BATS_TEST_TMPDIR/sed.log"
  
  # Verify grub config was regenerated
  grep -q "grub2-mkconfig: -o /boot/grub2/grub.cfg" "$BATS_TEST_TMPDIR/grub2-mkconfig.log"
}

@test "setup.sh sudoers_setup creates correct configuration" {
  # Source main script with modified paths
  source "$BATS_TEST_TMPDIR/setup_test.sh"
  
  run sudoers_setup
  
  [ "$status" -eq 0 ]
  
  # Verify sudoers file was created
  [ -f "$sudoers_file" ]
  
  # Verify content
  grep -q "developer ALL=(ALL) NOPASSWD: /opt/borg/home-borgbackup.sh" "$sudoers_file"
  grep -q "timestamp_type=global" "$sudoers_file"
  grep -q "timestamp_timeout=20" "$sudoers_file"
  
  # Verify permissions
  local perms=$(stat -c "%a" "$sudoers_file")
  [ "$perms" = "440" ]
}

@test "setup.sh tcp_bbr_setup creates network configuration" {
  # Source main script with modified paths
  source "$BATS_TEST_TMPDIR/setup_test.sh"
  
  run tcp_bbr_setup
  
  [ "$status" -eq 0 ]
  
  # Verify sysctl file was created
  [ -f "$tcp_bbr" ]
  
  # Check parameters were set correctly
  grep -q "net.core.default_qdisc = fq" "$tcp_bbr"
  grep -q "net.ipv4.tcp_congestion_control = bbr" "$tcp_bbr"
}

@test "setup.sh installs system-specific packages for desktop" {
  # Source main script with modified paths
  source "$BATS_TEST_TMPDIR/setup_test.sh"
  
  # Mock as desktop system
  export MOCK_HOSTNAME="desktop"
  
  run install_system_specific_packages
  
  [ "$status" -eq 0 ]
  
  # Verify desktop packages installation was attempted
  grep -q "Mock dnf: install -y" "$BATS_TEST_TMPDIR/dnf.log"
}

@test "setup.sh installs system-specific packages for laptop" {
  # Source main script with modified paths
  source "$BATS_TEST_TMPDIR/setup_test.sh"
  
  # Mock as laptop system
  export MOCK_HOSTNAME="laptop"
  
  run install_system_specific_packages
  
  [ "$status" -eq 0 ]
  
  # Verify laptop packages installation was attempted
  grep -q "Mock dnf: install -y" "$BATS_TEST_TMPDIR/dnf.log"
}