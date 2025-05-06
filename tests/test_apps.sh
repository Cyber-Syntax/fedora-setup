#!/usr/bin/env bats
# tests/test_apps.sh - Unit tests for apps.sh using Bats

setup() {
  # Get the absolute path to the repository root
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

  # Create a temporary directory for test artifacts within the BATS_TMPDIR
  export BATS_TEST_TMPDIR=$(mktemp -d -p "${BATS_TMPDIR:-/tmp}" "browser_test.XXXXXX")

  # Create a fake filesystem structure inside tests directory.
  export MOCK_ROOT="$BATS_TEST_TMPDIR/root"
  mkdir -p "$MOCK_ROOT/etc/yum.repos.d" "$MOCK_ROOT/usr/bin" "$MOCK_ROOT/usr/share/applications"

  export MOCK_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$MOCK_HOME/.local/share/applications" "$MOCK_HOME/.mozilla/firefox"

  # Create a fake Firefox profile directory with a dummy file inside.
  export firefox_profile="$MOCK_HOME/.mozilla/firefox/sq1asdgasd3124"
  mkdir -p "$firefox_profile"
  echo "dummy profile content" >"$firefox_profile/dummy.txt"
  
  # Set PROFILE variable which is used in apps.sh
  export PROFILE="sq1asdgasd3124"

  # Set test-specific variables.
  export librewolf_dir="$MOCK_HOME/.librewolf"
  mkdir -p "$librewolf_dir"
  export librewolf_profile="$librewolf_dir/profile.ini"

  # Override environment variables for paths.
  export REPO_DIR="$MOCK_ROOT/etc/yum.repos.d"
  export USER_HOME="$MOCK_HOME"
  export USER_DESKTOP_DIR="$MOCK_HOME/.local/share/applications"
  # Point the system desktop file to a file inside MOCK_ROOT.
  export DESKTOP_SYSTEM_FILE="$MOCK_ROOT/usr/share/applications/brave-browser.desktop"

  # Create a fake system Brave desktop file.
  echo 'Exec=/usr/bin/brave-browser-stable' >"$DESKTOP_SYSTEM_FILE"

  # Insert our mocks folder into PATH so calls to sudo dnf, curl, and pkexec are intercepted.
  export PATH="$REPO_ROOT/tests/mocks:$PATH"

  # Override USER variable to match current user for ownership operations
  export USER=$(whoami)
  
  # Create a dnf.log file in the test directory
  touch "$BATS_TEST_TMPDIR/sudo dnf.log"
  
  # Mock the chown command for tests
  function chown() {
    # Do nothing, just pretend we changed ownership
    echo "Mock chown called with: $*" >> "$BATS_TEST_TMPDIR/chown.log"
    return 0
  }
  export -f chown

  # Source the production script
  source "${REPO_ROOT}/src/apps.sh" || {
    echo "Failed to source apps.sh"
    return 1
  }
}

teardown() {
  # Clean up the temporary directory
  if [[ -d "$BATS_TEST_TMPDIR" ]]; then
    rm -rf "$BATS_TEST_TMPDIR"
  fi
}

@test "install_librewolf creates repo file, copies firefox profile, and writes profile.ini" {
  # Make sure DNF log will be created inside the test dir
  touch "$BATS_TEST_TMPDIR/sudo dnf.log"
  
  run install_librewolf

  # Check that the Librewolf repo file has been created.
  [ -f "$REPO_DIR/librewolf.repo" ]

  # Check that the sudo dnf mock ran and logged properly
  [ -f "$BATS_TEST_TMPDIR/sudo dnf.log" ]
  grep -q "install -y librewolf" "$BATS_TEST_TMPDIR/sudo dnf.log"
  
  # Verify that the Firefox profile (represented by the dummy file) was copied.
  [ -d "$librewolf_dir/$PROFILE" ]
  [ -f "$librewolf_dir/$PROFILE/dummy.txt" ]

  # Verify that profile.ini was written.
  [ -f "$librewolf_profile" ]
  grep -q "Default=$PROFILE" "$librewolf_profile"
}

@test "install_brave modifies desktop file in USER_DESKTOP_DIR" {
  # Ensure that no user desktop file exists yet.
  rm -f "$USER_DESKTOP_DIR/brave-browser.desktop"

  run install_brave

  # Check that the user's desktop file is created in USER_DESKTOP_DIR.
  local desktop_file="$USER_DESKTOP_DIR/brave-browser.desktop"
  [ -f "$desktop_file" ]

  # Verify that the file now contains the additional parameter.
  grep -q -- "--password-store=basic" "$desktop_file"
}

@test "install_auto_cpufreq clones repository and runs installer successfully" {
  # Ensure git.log doesn't exist
  rm -f "$BATS_TEST_TMPDIR/git.log"
  
  # Run the function
  run install_auto_cpufreq
  
  # Check that the function succeeded
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/git.log" ]
  
  # Check that git clone was called with the correct parameters
  grep -q "git clone https://github.com/AdnanHodzic/auto-cpufreq.git" "$BATS_TEST_TMPDIR/git.log"
  
  # Success message should be output
  echo "$output" | grep -q "auto-cpufreq installation completed"
}

@test "install_auto_cpufreq handles git clone failure" {
  # Set environment variable to make git mock fail
  export FAIL_GIT_CLONE=true
  
  # Run the function
  run install_auto_cpufreq
  
  # Check that the function failed
  [ "$status" -eq 1 ]
  
  # Error message should be output
  echo "$output" | grep -q "Failed to clone auto-cpufreq repository"
  
  # Reset the environment variable
  unset FAIL_GIT_CLONE
}

@test "install_auto_cpufreq handles installer failure" {
  # Set environment variable to make installer mock fail
  export INSTALLER_EXIT_CODE=1
  
  # Run the function
  run install_auto_cpufreq
  
  # Check that the function failed
  [ "$status" -eq 1 ]
  
  # Error message should be output
  echo "$output" | grep -q "auto-cpufreq installation failed"
  
  # Reset the environment variable
  unset INSTALLER_EXIT_CODE
}
