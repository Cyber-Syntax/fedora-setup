#!/usr/bin/env bats

# Setup test environment before each test
setup() {
  # Create a temporary test directory
  export BATS_TMPDIR="$(mktemp -d)"
  export XDG_CONFIG_HOME="${BATS_TMPDIR}/config"
  export FEDORA_SETUP_DIR="${BATS_TMPDIR}/fedora-setup"
  
  # Mock the logging functions to avoid polluting test output
  mkdir -p "${FEDORA_SETUP_DIR}/src"
  cat > "${FEDORA_SETUP_DIR}/src/logging.sh" <<'EOF'
log_info() { echo "INFO: $*"; }
log_error() { echo "ERROR: $*"; }
log_debug() { echo "DEBUG: $*"; }
log_warn() { echo "WARN: $*"; }
EOF

  # Create a modified version of config.sh that skips interactive prompts
  create_noninteractive_config_script
  
  # Create configs directory for fallback
  mkdir -p "${FEDORA_SETUP_DIR}/configs"
  
  # Create mock configs for testing
  create_mock_config_files
  
  # Change to test directory
  cd "${FEDORA_SETUP_DIR}"
  
  # Mock external commands
  mock_external_commands
}

# Create a modified, non-interactive version of config.sh for testing
create_noninteractive_config_script() {
  mkdir -p "${FEDORA_SETUP_DIR}/src"
  
  # Start with the original
  cp "src/config.sh" "${FEDORA_SETUP_DIR}/src/config.sh.orig"
  
  # Create a non-interactive version by replacing read prompts
  sed 's/read -p "[^"]*" answer/answer="y"/g' "src/config.sh" > "${FEDORA_SETUP_DIR}/src/config.sh"
  
  # Also replace "Press Enter to continue" prompt
  sed -i 's/read -p "Press Enter to continue[^"]*" answer/: # Skip prompt/g' "${FEDORA_SETUP_DIR}/src/config.sh"
  
  # Disable the automatic init_config call at the end
  sed -i 's/# Initialize configuration/# Do not auto-initialize for tests/g' "${FEDORA_SETUP_DIR}/src/config.sh"
  sed -i 's/init_config/# init_config -- disabled for tests/g' "${FEDORA_SETUP_DIR}/src/config.sh"
}

# Create mock configuration files for testing
create_mock_config_files() {
  # Create mock packages.json
  mkdir -p "${FEDORA_SETUP_DIR}/configs"
  cat > "${FEDORA_SETUP_DIR}/configs/packages.json" <<'EOF'
{
  "core": ["curl", "wget", "ufw"],
  "qtile": ["feh", "picom", "i3lock"],
  "flatpak": ["app1", "app2"]
}
EOF

  # Create mock variables.json
  cat > "${FEDORA_SETUP_DIR}/configs/variables.json" <<'EOF'
{
  "user": "testuser",
  "session": "qtile",
  "laptop_ip": "192.168.1.100",
  "hostnames": {
    "desktop": "test-desktop",
    "laptop": "test-laptop"
  },
  "browser": {
    "firefox_profile": "test.profile",
    "firefox_profile_path": "/home/testuser/.mozilla/firefox/test.profile",
    "librewolf_dir": "/home/testuser/.librewolf/",
    "librewolf_profile": "/home/testuser/.librewolf/profiles.ini"
  },
  "system": {
    "mirror_country": "us",
    "repo_dir": "/etc/yum.repos.d"
  }
}
EOF
}

# Mock external commands that might be called
mock_external_commands() {
  # Create a modified PATH to include our mock binaries
  mkdir -p "${BATS_TMPDIR}/mockbin"
  export PATH="${BATS_TMPDIR}/mockbin:$PATH"
  
  # Mock jq command
  cat > "${BATS_TMPDIR}/mockbin/jq" <<'EOF'
#!/bin/bash
case "$*" in
  *".user"*)
    echo "testuser"
    ;;
  *".core[]"*)
    echo -e "curl\nwget\nufw"
    ;;
  *".qtile[]"*)
    echo -e "feh\npicom\ni3lock"
    ;;
  *".flatpak[]"*)
    echo -e "app1\napp2"
    ;;
  *".apps[]"*)
    echo -e "app1\napp2"
    ;;
  *".dev[]"*)
    echo -e "dev1\ndev2"
    ;;
  *".desktop[]"*)
    echo -e "desktop1\ndesktop2"
    ;;
  *".laptop[]"*)
    echo -e "laptop1\nlaptop2"
    ;;
  *".session"*)
    echo "qtile"
    ;;
  *".laptop_ip"*)
    echo "192.168.1.100"
    ;;
  *".hostnames.desktop"*)
    echo "test-desktop"
    ;;
  *".hostnames.laptop"*)
    echo "test-laptop"
    ;;
  *".browser.firefox_profile"*)
    echo "test.profile"
    ;;
  *".browser.firefox_profile_path"*)
    echo "/home/testuser/.mozilla/firefox/test.profile"
    ;;
  *".browser.librewolf_dir"*)
    echo "/home/testuser/.librewolf/"
    ;;
  *".browser.librewolf_profile"*)
    echo "/home/testuser/.librewolf/profiles.ini"
    ;;
  *".system.mirror_country"*)
    echo "us"
    ;;
  *".system.repo_dir"*)
    echo "/etc/yum.repos.d"
    ;;
  *)
    echo "mock_value"
    ;;
esac
EOF
  chmod +x "${BATS_TMPDIR}/mockbin/jq"
  
  # Mock sudo command
  cat > "${BATS_TMPDIR}/mockbin/sudo" <<'EOF'
#!/bin/bash
echo "sudo would run: $*"
exit 0
EOF
  chmod +x "${BATS_TMPDIR}/mockbin/sudo"
  
  # Mock hostname command
  cat > "${BATS_TMPDIR}/mockbin/hostname" <<'EOF'
#!/bin/bash
echo "test-hostname"
exit 0
EOF
  chmod +x "${BATS_TMPDIR}/mockbin/hostname"
  
  # Mock command that checks if jq exists
  function command() {
    if [[ "$*" == *"jq"* ]]; then
      return 0  # jq is available
    fi
    /usr/bin/command "$@"
  }
  export -f command
}

# Cleanup after each test
teardown() {
  # Clean up temp directory
  rm -rf "$BATS_TMPDIR"
}

# Helper to run functions from config.sh
run_config_function() {
  local func_name="$1"
  shift
  
  # Source the non-interactive config script
  source "${FEDORA_SETUP_DIR}/src/config.sh"
  
  # Call the requested function
  "$func_name" "$@"
}

# Test create_default_packages_json
@test "create_default_packages_json creates a valid JSON file" {
  local test_file="${BATS_TMPDIR}/test_packages.json"
  
  # Run the function
  run run_config_function create_default_packages_json "$test_file"
  [ "$status" -eq 0 ]
  
  # Check file was created
  [ -f "$test_file" ]
  
  # Check for required sections in the file
  grep -q '"core"' "$test_file"
  grep -q '"qtile"' "$test_file"
  grep -q '"flatpak"' "$test_file"
}

# Test create_default_variables_json
@test "create_default_variables_json creates a valid JSON file" {
  local test_file="${BATS_TMPDIR}/test_variables.json"
  
  # Run the function
  run run_config_function create_default_variables_json "$test_file"
  [ "$status" -eq 0 ]
  
  # Check file was created
  [ -f "$test_file" ]
  
  # Check for required sections
  grep -q '"user"' "$test_file"
  grep -q '"hostnames"' "$test_file"
  grep -q '"browser"' "$test_file"
  grep -q '"system"' "$test_file"
}
# Test load_json_config with existing file
@test "load_json_config returns path for existing file" {
  # Create a config dir and file directly in the test directory
  mkdir -p "${XDG_CONFIG_HOME}/fedora-setup"
  echo '{"test":"value"}' > "${XDG_CONFIG_HOME}/fedora-setup/test.json"

  # Create a modified version of load_json_config to avoid interactive prompts
  local output
  output=$(run_config_function load_json_config "test.json")

  # Check if the function correctly found our file
  [ -n "$output" ]
  [ "$output" = "${XDG_CONFIG_HOME}/fedora-setup/test.json" ]
}

# Test load_json_config with fallback to configs directory
@test "load_json_config falls back to configs directory" {
  # Remove any config in XDG_CONFIG_HOME
  rm -rf "${XDG_CONFIG_HOME}/fedora-setup"
  
  # Create test file in configs directory
  mkdir -p "${FEDORA_SETUP_DIR}/configs"
  echo '{"test":"fallback"}' > "${FEDORA_SETUP_DIR}/configs/fallback.json"
  
  # Run the function
  run run_config_function load_json_config "fallback.json"
  [ "$status" -eq 0 ]
  [ "$output" = "./configs/fallback.json" ]
}

# Test parse_json with valid input
@test "parse_json extracts values from JSON" {
  # Create a test JSON file
  local test_file="${BATS_TMPDIR}/test_parse.json"
  cat > "$test_file" <<EOF
{
  "string": "value",
  "array": [1, 2, 3],
  "nested": {
    "key": "nested_value"
  }
}
EOF
  
  # Test with mocked jq responses
  run run_config_function parse_json "$test_file" ".string"
  [ "$status" -eq 0 ]
  # The result will come from our mocked jq which returns "mock_value"
  [ "$output" = "mock_value" ]
}

# Test load_variables
@test "load_variables sets up environment variables" {
  # First create the required config files to avoid interactive prompts
  mkdir -p "${XDG_CONFIG_HOME}/fedora-setup"
  cp "${FEDORA_SETUP_DIR}/configs/variables.json" "${XDG_CONFIG_HOME}/fedora-setup/"
  
  # Run load_variables
  run_config_function load_variables
  
  # Variables should now be set from our mocked responses
  [ "$USER" = "testuser" ]
  [ "$SESSION" = "qtile" ]
  [ "$hostname_desktop" = "test-desktop" ]
  [ "$hostname_laptop" = "test-laptop" ]
}

# Test load_package_arrays
@test "load_package_arrays loads all package arrays" {
  # First create the required config files to avoid interactive prompts
  mkdir -p "${XDG_CONFIG_HOME}/fedora-setup"
  cp "${FEDORA_SETUP_DIR}/configs/packages.json" "${XDG_CONFIG_HOME}/fedora-setup/"
  
  # Run load_package_arrays
  run_config_function load_package_arrays
  
  # Arrays should now be set from our mocked responses
  [ "${#CORE_PACKAGES[@]}" -eq 3 ]
  [ "${CORE_PACKAGES[0]}" = "curl" ]
  [ "${CORE_PACKAGES[1]}" = "wget" ]
  [ "${CORE_PACKAGES[2]}" = "ufw" ]
  
  [ "${#QTILE_PACKAGES[@]}" -eq 3 ]
  [ "${QTILE_PACKAGES[0]}" = "feh" ]
  [ "${QTILE_PACKAGES[1]}" = "picom" ]
  [ "${QTILE_PACKAGES[2]}" = "i3lock" ]
}

# Test install_qtile_packages
@test "install_qtile_packages calls dnf install" {
  # Set up QTILE_PACKAGES array
  QTILE_PACKAGES=("feh" "picom" "i3lock")
  
  # Run install_qtile_packages
  run run_config_function install_qtile_packages
  
  # Check if sudo dnf install was called
  [[ "$output" == *"sudo would run: dnf install -y feh picom i3lock"* ]]
}

# Test check_and_create_config
@test "check_and_create_config creates directory and files" {
  # Run check_and_create_config
  run run_config_function check_and_create_config
  
  # Verify directory was created
  [ -d "${XDG_CONFIG_HOME}/fedora-setup" ]
  
  # Verify files were created
  [ -f "${XDG_CONFIG_HOME}/fedora-setup/packages.json" ]
  [ -f "${XDG_CONFIG_HOME}/fedora-setup/variables.json" ]
}
