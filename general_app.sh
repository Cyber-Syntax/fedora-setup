#!/bin/bash

install_librewolf() {
  echo "Installing Librewolf..."
  curl -fsSL https://repo.librewolf.net/librewolf.repo | pkexec tee /etc/yum.repos.d/librewolf.repo >/dev/null
  dnf install -y librewolf
  echo "Librewolf installation completed."
}

install_lazygit() {
  echo "Installing Lazygit..."
  dnf copr enable atim/lazygit -y
  dnf install -y lazygit
  echo "Lazygit installation completed."
}

# Disable keyring prompt for Brave Browser.
modify_brave_desktop() {
  # Local desktop file (TEST: using home version applications .desktop file)
  local desktop_file="$HOME/.local/share/applications/brave-browser.desktop"
  if [[ ! -f "$desktop_file" ]]; then
    echo "Error: $desktop_file not found. Please check the path."
    return 1
  fi

  # Check if the parameter is already present.
  if grep -q -- "--password-store=basic" "$desktop_file"; then
    echo "Brave desktop file already contains '--password-store=basic'."
  else
    # Insert the argument after the binary path.
    sed -i 's|^\(Exec=.*brave-browser-stable\)\(.*\)|\1 --password-store=basic\2|' "$desktop_file"
    echo "Modified $desktop_file to include '--password-store=basic'."
  fi
}

install_brave() {
  echo "Installing Brave Browser..."
  dnf install -y dnf-plugins-core
  echo "Adding Brave Browser repository..."
  dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
  dnf install -y brave-browser
  echo "Brave Browser installation completed."

  echo "Modifying Brave Browser desktop file for password-store basic..."
  modify_brave_desktop
}
