#!/bin/bash

#FIXME: Updating and loading repositories:
#  LibreWolf Software Repository                                                                                                 100% |  12.2 KiB/s |   3.8 KiB |  00m00s
# >>> Librepo error: repomd.xml GPG signature verification error: Signing key not found
#  https://repo.librewolf.net/pubkey.gpg
#  but then insert it ?
# Importing OpenPGP key 0x2B12EF16:
#  UserID     : "LibreWolf Maintainers <gpg@librewolf.net>"
#  Fingerprint: <cleaned_by_me>
#  From       : https://repo.librewolf.net/pubkey.gpg
# The key was successfully imported.
#  LibreWolf Software Repository                                                                                                 100% |  21.9 KiB/s |  10.8 KiB |  00m00s
# Repositories loaded.
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
  # Use eval to properly expand home directory
  local user_desktop_dir="$(eval echo ~$USER)/.local/share/applications"
  local system_desktop_file="/usr/share/applications/brave-browser.desktop"
  local user_desktop_file="$user_desktop_dir/brave-browser.desktop"

  # Create user directory if it doesn't exist
  if [[ ! -d "$user_desktop_dir" ]]; then
    mkdir -p "$user_desktop_dir" || {
      echo "Error: Failed to create user applications directory" >&2
      return 1
    }
  fi

  # Use system desktop file if user copy doesn't exist
  if [[ ! -f "$user_desktop_file" ]]; then
    if [[ -f "$system_desktop_file" ]]; then
      echo "Copying system desktop file to user directory..."
      cp "$system_desktop_file" "$user_desktop_file" || {
        echo "Error: Failed to copy desktop file" >&2
        return 1
      }
    else
      echo "Error: Brave desktop file not found at:" >&2
      echo "System: $system_desktop_file" >&2
      echo "User: $user_desktop_file" >&2
      return 1
    fi
  fi

  # Use temporary file for safe editing
  local temp_file=$(mktemp)
  cp "$user_desktop_file" "$temp_file" || return 1

  # Check for existing modification
  if grep -q -- "--password-store=basic" "$temp_file"; then
    echo "Desktop file already modified - no changes needed"
    rm "$temp_file"
    return 0
  fi

  # Insert argument after executable path
  sed -i 's|^Exec=/usr/bin/brave-browser-stable|& --password-store=basic|' "$temp_file" || {
    echo "Error: Failed to modify desktop file" >&2
    rm "$temp_file"
    return 1
  }

  # Replace original file preserving permissions
  chmod --reference="$user_desktop_file" "$temp_file"
  mv "$temp_file" "$user_desktop_file" || {
    echo "Error: Failed to update desktop file" >&2
    return 1
  }

  echo "Successfully modified Brave desktop file"
  return 0
}
install_brave() {
  echo "Installing Brave Browser..."
  dnf install -y dnf-plugins-core
  echo "Adding Brave Browser repository..."

  # add if repo not exist
  if [[ ! -f "/etc/yum.repos.d/brave-browser.repo" ]]; then
    dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
  fi

  dnf install -y brave-browser
  echo "Brave Browser installation completed."

  echo "Modifying Brave Browser desktop file for password-store basic..."
  modify_brave_desktop
}
