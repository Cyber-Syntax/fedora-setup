#!/bin/bash

# Tweaks DNF configuration to improve performance.
speed_up_dnf() {
  echo "Configuring DNF for improve performance..."
  local dnf_conf="/etc/dnf/dnf.conf"
  # Backup current dnf.conf if no backup exists.
  if [[ ! -f "${dnf_conf}.bak" ]]; then
    cp "$dnf_conf" "${dnf_conf}.bak"
  fi
  # Append settings if not already present.
  grep -q '^max_parallel_downloads=20' "$dnf_conf" || echo 'max_parallel_downloads=20' >>"$dnf_conf"
  grep -q '^pkg_gpgcheck=True' "$dnf_conf" || echo 'pkg_gpgcheck=True' >>"$dnf_conf"
  grep -q '^skip_if_unavailable=True' "$dnf_conf" || echo 'skip_if_unavailable=True' >>"$dnf_conf"
  grep -q '^minrate=50k' "$dnf_conf" || echo 'minrate=50k' >>"$dnf_conf"
  grep -q '^timeout=15' "$dnf_conf" || echo 'timeout=15' >>"$dnf_conf"
  grep -q '^retries=5' "$dnf_conf" || echo 'retries=5' >>"$dnf_conf"

  echo "DNF configuration updated."
}

switch_ufw_setup() {
  echo "Switching to UFW from firewalld..."
  systemctl disable --now firewalld
  systemctl enable --now ufw
  echo "UFW installation completed."
  echo "Updating UFW rules..."
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow from 192.168.1.0/16
  ufw allow ssh
  echo "Opening ports for Syncthing..."
  ufw allow 22000
  ufw allow 21027/udp
  echo "Syncthing ports opened. Check UFW status with 'ufw status verbose'."
}

# Swaps ffmpeg-free with ffmpeg if ffmpeg-free is installed.
ffmpeg_swap() {
  echo "Checking for ffmpeg-free package..."
  if dnf list installed ffmpeg-free &>/dev/null; then
    echo "Swapping ffmpeg-free with ffmpeg..."
    dnf swap ffmpeg-free ffmpeg --allowerasing -y
    echo "ffmpeg swap completed."
  else
    echo "ffmpeg-free is not installed; skipping swap."
  fi
}

# Enables RPM Fusion free and nonfree repositories.
enable_rpm_fusion() {
  echo "Enabling RPM Fusion repositories..."
  local fedora_version
  fedora_version=$(rpm -E %fedora)

  local free_repo_count
  local nonfree_repo_count
  free_repo_count=$(dnf repolist | awk '$1=="rpmfusion-free" {print $1}' | wc -l)
  nonfree_repo_count=$(dnf repolist | awk '$1=="rpmfusion-nonfree" {print $1}' | wc -l)

  # Check if both "rpmfusion-free" and "rpmfusion-nonfree" are already enabled.
  if [[ $free_repo_count -gt 0 && $nonfree_repo_count -gt 0 ]]; then
    echo "RPM Fusion free and nonfree repositories are already enabled. Skipping installation."
    return 0
  fi

  # Otherwise, install the repositories.
  dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_version}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_version}.noarch.rpm"

  dnf upgrade --refresh -y
  dnf group upgrade -y core
  dnf install -y rpmfusion-free-release-tainted rpmfusion-nonfree-release-tainted dnf-plugins-core
  echo "RPM Fusion repositories enabled."
}
