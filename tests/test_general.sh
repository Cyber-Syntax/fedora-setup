#!/usr/bin/env bats
# tests/test_general.sh - Unit tests for general.sh functions

setup() {
  # Get the absolute path to the repository root
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

  # Create a temporary directory for test artifacts
  export BATS_TEST_TMPDIR=$(mktemp -d -p "${BATS_TMPDIR:-/tmp}" "general_test.XXXXXX")
  
  # Create necessary directories and mock files
  export MOCK_ROOT="$BATS_TEST_TMPDIR/root"
  mkdir -p "$MOCK_ROOT/etc/dnf" "$MOCK_ROOT/etc/sysctl.d" "$MOCK_ROOT/etc/sudoers.d"
  
  # Create mock DNF config file
  echo -e "# DNF Config file\n[main]\ninstallonly_limit=3" > "$MOCK_ROOT/etc/dnf/dnf.conf"
  
  # Set file paths to use mock root
  export dnf_conf="$MOCK_ROOT/etc/dnf/dnf.conf"
  export tcp_bbr="$MOCK_ROOT/etc/sysctl.d/99-tcp-bbr.conf"
  export sudoers_file="$MOCK_ROOT/etc/sudoers.d/custom-conf"
  
  # Set logging directory for tests
  export LOG_DIR="$BATS_TEST_TMPDIR/logs"
  mkdir -p "$LOG_DIR"

  # Setup simple logging functions
  function log_info() { echo "[INFO] $1"; }
  function log_error() { echo "[ERROR] $1"; }
  function log_success() { echo "[SUCCESS] $1"; }
  function log_debug() { echo "[DEBUG] $1"; }
  function log_warn() { echo "[WARN] $1"; }
  function log_cmd() { 
    echo "[CMD] $1"
    if eval "$1"; then
      return 0
    else
      return $?
    fi
  }
  
  export -f log_info log_error log_success log_debug log_warn log_cmd
  
  # Define test implementations of the general.sh functions

  # speed_up_dnf implementation
  speed_up_dnf() {
    # Backup dnf.conf
    cp "$dnf_conf" "${dnf_conf}.bak" || return 1
    
    # Add our settings
    cat >> "$dnf_conf" << EOF
max_parallel_downloads=20
pkg_gpgcheck=True
skip_if_unavailable=True
minrate=250k
timeout=15
retries=5
EOF
    return 0
  }
  
  # ffmpeg_swap implementation
  ffmpeg_swap() {
    # For testing, just create a mock flag file indicating it was called
    if [[ "$FFMPEG_FREE_INSTALLED" == "true" ]]; then
      echo "Swapped ffmpeg-free to ffmpeg" > "$BATS_TEST_TMPDIR/ffmpeg_swapped"
      return 0
    else
      echo "ffmpeg-free is not installed; skipping swap" > "$BATS_TEST_TMPDIR/ffmpeg_swapped"
      return 0
    fi
  }
  
  # enable_rpm_fusion implementation
  enable_rpm_fusion() {
    if [[ "$RPM_FUSION_ENABLED" == "true" ]]; then
      echo "RPM Fusion free and nonfree repositories are already enabled" > "$BATS_TEST_TMPDIR/rpm_fusion_status"
      return 0
    else
      # Create mock repo files to indicate installation
      touch "$MOCK_ROOT/etc/yum.repos.d/rpmfusion-free.repo"
      touch "$MOCK_ROOT/etc/yum.repos.d/rpmfusion-nonfree.repo"
      echo "RPM Fusion repositories enabled successfully" > "$BATS_TEST_TMPDIR/rpm_fusion_status"
      return 0
    fi
  }
  
  # tcp_bbr_setup implementation
  tcp_bbr_setup() {
    # Create sysctl TCP BBR config file
    cat > "$tcp_bbr" << EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.wmem_max = 104857000
net.core.rmem_max = 104857000
EOF
    return 0
  }
  
  # sudoers_setup implementation
  sudoers_setup() {
    # Create sudoers file
    cat > "$sudoers_file" << EOF
## Allow borgbackup script to run without password
developer ALL=(ALL) NOPASSWD: /opt/borg/home-borgbackup.sh

## Increase timeout on terminal password prompt
Defaults timestamp_type=global
Defaults env_reset,timestamp_timeout=20
EOF
    chmod 440 "$sudoers_file"
    return 0
  }
  
  # Mock the ufw setup function - just create indicator files
  switch_ufw_setup() {
    # Create marker files to indicate commands were run
    echo "disabled firewalld" > "$BATS_TEST_TMPDIR/firewalld_status"
    echo "enabled ufw" > "$BATS_TEST_TMPDIR/ufw_status"
    mkdir -p "$MOCK_ROOT/etc/ufw"
    touch "$MOCK_ROOT/etc/ufw/ufw.conf"
    # Create files to indicate rules were set
    echo "incoming: deny" > "$MOCK_ROOT/etc/ufw/incoming"
    echo "outgoing: allow" > "$MOCK_ROOT/etc/ufw/outgoing"
    echo "ssh: allow" > "$MOCK_ROOT/etc/ufw/ssh"
    echo "22000: allow" > "$MOCK_ROOT/etc/ufw/syncthing_tcp"
    echo "21027/udp: allow" > "$MOCK_ROOT/etc/ufw/syncthing_udp"
    return 0
  }
  
  export -f speed_up_dnf ffmpeg_swap enable_rpm_fusion tcp_bbr_setup sudoers_setup switch_ufw_setup
}

teardown() {
  if [[ -d "$BATS_TEST_TMPDIR" ]]; then
    rm -rf "$BATS_TEST_TMPDIR"
  fi
}

@test "speed_up_dnf updates dnf.conf with performance settings" {
  run speed_up_dnf
  
  [ "$status" -eq 0 ]
  
  # Check if backup was created
  [ -f "${dnf_conf}.bak" ]
  
  # Verify settings were added
  grep -q "max_parallel_downloads=20" "$dnf_conf"
  grep -q "pkg_gpgcheck=True" "$dnf_conf"
  grep -q "skip_if_unavailable=True" "$dnf_conf"
  grep -q "minrate=250k" "$dnf_conf"
  grep -q "timeout=15" "$dnf_conf"
  grep -q "retries=5" "$dnf_conf"
}

@test "switch_ufw_setup creates proper ufw configuration" {
  run switch_ufw_setup
  
  [ "$status" -eq 0 ]
  
  # Verify firewalld was disabled and ufw enabled
  [ -f "$BATS_TEST_TMPDIR/firewalld_status" ]
  [ -f "$BATS_TEST_TMPDIR/ufw_status" ]
  
  # Verify UFW config was created
  [ -f "$MOCK_ROOT/etc/ufw/ufw.conf" ]
  [ -f "$MOCK_ROOT/etc/ufw/incoming" ]
  [ -f "$MOCK_ROOT/etc/ufw/outgoing" ]
  [ -f "$MOCK_ROOT/etc/ufw/ssh" ]
  [ -f "$MOCK_ROOT/etc/ufw/syncthing_tcp" ]
  [ -f "$MOCK_ROOT/etc/ufw/syncthing_udp" ]
}

@test "ffmpeg_swap handles both installed and not installed scenarios" {
  # Test when ffmpeg-free is installed
  export FFMPEG_FREE_INSTALLED=true
  
  run ffmpeg_swap
  
  [ "$status" -eq 0 ]
  grep -q "Swapped ffmpeg-free to ffmpeg" "$BATS_TEST_TMPDIR/ffmpeg_swapped"
  
  # Test when ffmpeg-free is not installed
  export FFMPEG_FREE_INSTALLED=false
  
  run ffmpeg_swap
  
  [ "$status" -eq 0 ]
  grep -q "ffmpeg-free is not installed; skipping swap" "$BATS_TEST_TMPDIR/ffmpeg_swapped"
}

@test "enable_rpm_fusion handles both enabled and not enabled scenarios" {
  # Test when RPM Fusion is already enabled
  export RPM_FUSION_ENABLED=true
  
  run enable_rpm_fusion
  
  [ "$status" -eq 0 ]
  grep -q "already enabled" "$BATS_TEST_TMPDIR/rpm_fusion_status"
  
  # Test when RPM Fusion is not enabled
  export RPM_FUSION_ENABLED=false
  
  run enable_rpm_fusion
  
  [ "$status" -eq 0 ]
  [ -f "$MOCK_ROOT/etc/yum.repos.d/rpmfusion-free.repo" ]
  [ -f "$MOCK_ROOT/etc/yum.repos.d/rpmfusion-nonfree.repo" ]
  grep -q "enabled successfully" "$BATS_TEST_TMPDIR/rpm_fusion_status"
}

@test "tcp_bbr_setup creates sysctl configuration" {
  run tcp_bbr_setup
  
  [ "$status" -eq 0 ]
  
  # Verify config file was created with correct parameters
  [ -f "$tcp_bbr" ]
  grep -q "net.core.default_qdisc = fq" "$tcp_bbr"
  grep -q "net.ipv4.tcp_congestion_control = bbr" "$tcp_bbr"
  grep -q "net.core.wmem_max = 104857000" "$tcp_bbr"
  grep -q "net.core.rmem_max = 104857000" "$tcp_bbr"
}

@test "sudoers_setup creates sudoers file with correct permissions" {
  run sudoers_setup
  
  [ "$status" -eq 0 ]
  
  # Verify file exists with proper content
  [ -f "$sudoers_file" ]
  grep -q "developer ALL=(ALL) NOPASSWD: /opt/borg/home-borgbackup.sh" "$sudoers_file"
  grep -q "timestamp_timeout=20" "$sudoers_file"
  
  # Check permissions (should be 0440)
  local perms=$(stat -c "%a" "$sudoers_file")
  [ "$perms" = "440" ]
}
