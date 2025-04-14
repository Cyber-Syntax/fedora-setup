#!/usr/bin/env bash

source src/logging.sh

#TODO: Need to automate update to ollama?
install_ollama() {
  log_info "Installing Ollama..."

  # Check if Ollama is already installed
  if command -v ollama &>/dev/null; then
    log_info "Ollama is already installed"
    return 0
  fi

  log_debug "Downloading and running Ollama install script..."
  # Execute curl command directly instead of passing it to log_cmd with pipes
  if ! curl -fsSL https://ollama.com/install.sh | sed 's/--add-repo/addrepo/' | sh; then
    log_error "Failed to install Ollama"
    return 1
  fi

  # Verify installation
  if command -v ollama &>/dev/null; then
    log_info "Ollama installation completed successfully"
    return 0
  else
    log_error "Ollama binary not found after installation"
    return 1
  fi
}

#TEST: Currently only for desktop
borgbackup_setup() {
  # send sh script to /opt/borg/home-borgbackup.sh
  log_info "Moving borgbackup script to /opt/borg/home-borgbackup.sh..."

  local dir_borg_script="/opt/borg/home-borgbackup.sh"
  local borg_script_file="./configs/borg/home-borgbackup.sh"
  local dir_borg_timer="/etc/systemd/system/borgbackup-home.timer"
  local dir_borg_service="/etc/systemd/system/borgbackup-home.service"
  local borg_timer_file="./configs/borg/borgbackup-home.timer"
  local borg_service_file="./configs/borg/borgbackup-home.service"

  # check opt/borg directory
  if [ ! -d /opt/borg ]; then
    log_debug "Creating /opt/borg directory..."
    sudo mkdir -p /opt/borg
  fi
  # copy script to /opt/borg
  if [ ! -f /opt/borg/home-borgbackup.sh ]; then
    log_debug "Copying home-borgbackup.sh to /opt/borg..."
    if ! sudo cp "$borg_script_file" "$dir_borg_script"; then
      log_error "Failed to copy home-borgbackup.sh to /opt/borg"
      return 1
    fi
  else
    log_debug "home-borgbackup.sh already exists in /opt/borg"
  fi

  # check if borgbackup is installed
  if ! command -v borg &>/dev/null; then
    log_debug "Borgbackup is not installed, installing..."
    if ! sudo dnf install -y borgbackup; then
      log_error "Failed to install Borgbackup"
      return 1
    fi
  else
    log_debug "Borgbackup is already installed"
  fi

  # cp timer, service
  if ! sudo cp "$borg_service_file" "$dir_borg_service"; then
    log_error "Failed to copy borgbackup service file"
    return 1
  fi

  if ! sudo cp "$borg_timer_file" "$dir_borg_timer"; then
    log_error "Failed to copy borgbackup timer file"
    return 1
  fi

  # enable and start timer
  log_debug "Enabling and starting borgbackup timer..."
  if ! sudo systemctl enable --now borgbackup.timer; then
    log_error "Failed to enable and start borgbackup timer"
    return 1
  fi

  # end if everything is ok
  log_info "Borgbackup setup completed successfully"
  log_debug "Borgbackup timer is enabled and started"
}

# Autologin for gdm
#NOTE: currently backlog
#TODO: Need to make $USER variable
gdm_auto_login() {
  log_info "Setting up GDM autologin..."
  local gdm_custom="/etc/gdm/custom.conf"

  # Check if user is root or has sudo privileges
  if [[ $EUID -ne 0 ]]; then
    log_error "This function must be run as root or with sudo privileges"
    return 1
  fi

  # Verify username is set
  if [[ -z "$USER" ]]; then
    log_error "USER environment variable is not set"
    return 1
  fi

  log_debug "Creating GDM configuration at $gdm_custom..."
  cat <<EOF | sudo tee "$gdm_custom" >/dev/null
[daemon]
WaylandEnable=false
DefaultSession=qtile.desktop
AutomaticLoginEnable=True
AutomaticLogin=$USER
EOF

  # Verify file was created and has correct content
  if [[ ! -f "$gdm_custom" ]]; then
    log_error "GDM configuration file was not created"
    return 1
  fi

  log_info "GDM autologin setup completed successfully"
  return 0
}

# TEST: Setup zenpower for Ryzen 5000 series.
# This function enables the zenpower COPR repository and installs zenpower3 and zenmonitor3.
zenpower_setup() {
  log_info "Setting up zenpower for Ryzen 5000 series..."

  # Check if running on AMD CPU
  if ! grep -q "AMD" /proc/cpuinfo; then
    log_error "This system does not appear to have an AMD CPU"
    return 1
  fi

  log_debug "Enabling zenpower3 COPR repository..."
  if ! sudo dnf copr enable shdwchn10/zenpower3 -y; then
    log_error "Failed to enable zenpower3 COPR repository"
    return 1
  fi

  log_debug "Installing zenpower3 and zenmonitor3..."
  if ! sudo dnf install -y zenpower3 zenmonitor3; then
    log_error "Failed to install zenpower packages"
    return 1
  fi

  local blacklist_file="/etc/modprobe.d/zenpower.conf"
  log_debug "Creating k10temp blacklist file at $blacklist_file..."
  echo "blacklist k10temp" | sudo tee "$blacklist_file" >/dev/null
  if [ $? -ne 0 ]; then
    log_error "Failed to create k10temp blacklist file"
    return 1
  fi

  log_info "Zenpower setup completed successfully"
  log_debug "Note: Please verify if k10temp blacklisting is required for your system"
  return 0
}

# TEST: Install CUDA
nvidia_cuda_setup() {
  log_info "Setting up NVIDIA CUDA..."

  # Check if system has NVIDIA GPU
  if ! lspci | grep -i nvidia &>/dev/null; then
    log_error "No NVIDIA GPU detected in this system"
    return 1
  fi

  local arch
  arch=$(uname -m)
  local cuda_repo
  cuda_repo="https://developer.download.nvidia.com/compute/cuda/repos/fedora41/${arch}/cuda-fedora41.repo"

  log_debug "Adding CUDA repository..."
  if ! sudo dnf config-manager addrepo --from-repofile="$cuda_repo"; then
    log_error "Failed to add CUDA repository"
    return 1
  fi

  log_debug "Cleaning DNF cache..."
  if ! sudo dnf clean all; then
    log_error "Failed to clean DNF cache"
    return 1
  fi

  log_debug "Disabling nvidia-driver module..."
  if ! sudo dnf module disable -y nvidia-driver; then
    log_warn "Failed to disable nvidia-driver module - this might be normal on Fedora 41"
  fi

  log_debug "Setting package exclusions..."
  local exclude_pkgs="nvidia-driver,nvidia-modprobe,nvidia-persistenced,nvidia-settings,nvidia-libXNVCtrl,nvidia-xconfig"
  if ! sudo dnf config-manager setopt "cuda-fedora41-${arch}.exclude=${exclude_pkgs}"; then
    log_error "Failed to set package exclusions"
    return 1
  fi

  log_debug "Installing CUDA toolkit..."
  if ! sudo dnf -y install cuda-toolkit; then
    log_error "Failed to install CUDA toolkit"
    return 1
  fi

  # Verify installation
  if ! command -v nvcc &>/dev/null; then
    log_error "CUDA toolkit installation failed - nvcc not found"
    return 1
  fi

  log_info "CUDA setup completed successfully"
  log_debug "Note: You may need to install xorg-x11-drv-nvidia-cuda-libs package"
  return 0
}

# TEST: Switch nvidia-open
switch_nvidia_open() {
  log_info "Switching to NVIDIA open source drivers..."

  # Check if system has NVIDIA GPU
  if ! lspci | grep -i nvidia &>/dev/null; then
    log_error "No NVIDIA GPU detected in this system"
    return 1
  fi

  # Check for root privileges
  if [[ $EUID -ne 0 ]]; then
    log_error "This function must be run as root or with sudo privileges"
    return 1
  fi

  local nvidia_kmod_macro="/etc/rpm/macros.nvidia-kmod"
  log_debug "Creating NVIDIA kmod macro file..."
  echo "%_with_kmod_nvidia_open 1" | sudo tee "$nvidia_kmod_macro" >/dev/null
  if [ $? -ne 0 ]; then
    log_error "Failed to create NVIDIA kmod macro file"
    return 1
  fi

  local current_kernel
  current_kernel=$(uname -r)
  log_debug "Rebuilding NVIDIA modules for kernel $current_kernel..."
  if ! akmods --kernels "$current_kernel" --rebuild; then
    log_warn "Initial rebuild failed, attempting with --force..."
    if ! akmods --kernels "$current_kernel" --rebuild --force; then
      log_error "Failed to rebuild NVIDIA modules"
      return 1
    fi
  fi

  log_debug "Disabling RPMFusion non-free NVIDIA driver repository..."
  if ! sudo dnf --disablerepo rpmfusion-nonfree-nvidia-driver; then
    log_error "Failed to disable RPMFusion non-free NVIDIA driver repository"
    return 1
  fi

  log_info "NVIDIA open source driver setup completed"
  log_info "Please wait 10-20 minutes for the NVIDIA modules to build, then reboot"
  log_info "After reboot, verify installation with:"
  log_info "1. 'modinfo nvidia | grep license' - should show 'Dual MIT/GPL'"
  log_info "2. 'rpm -qa kmod-nvidia*' - should show kmod-nvidia-open package"

  return 0
}

# TEST: Setup VA-API for NVIDIA RTX series.
vaapi_setup() {
  log_info "Setting up VA-API for NVIDIA RTX series..."

  # Check if system has NVIDIA GPU
  if ! lspci | grep -i nvidia &>/dev/null; then
    log_error "No NVIDIA GPU detected in this system"
    return 1
  fi

  # Install required packages
  log_debug "Installing VA-API related packages..."
  local packages=(
    "meson"
    "libva-devel"
    "gstreamer1-plugins-bad-freeworld"
    "nv-codec-headers"
    "nvidia-vaapi-driver"
    "gstreamer1-plugins-bad-free-devel"
  )

  if ! sudo dnf install -y "${packages[@]}"; then
    log_error "Failed to install VA-API packages"
    return 1
  fi

  local env_file="/etc/environment"
  local env_vars=(
    "MOZ_DISABLE_RDD_SANDBOX=1"
    "LIBVA_DRIVER_NAME=nvidia"
    "__GLX_VENDOR_LIBRARY_NAME=nvidia"
  )

  log_debug "Setting up environment variables in $env_file..."

  # Check if variables already exist
  local need_append=false
  for var in "${env_vars[@]}"; do
    if ! grep -q "^${var}$" "$env_file" 2>/dev/null; then
      need_append=true
      break
    fi
  done

  if [[ "$need_append" == "true" ]]; then
    printf '%s\n' "${env_vars[@]}" | sudo tee -a "$env_file" >/dev/null
    if [ $? -ne 0 ]; then
      log_error "Failed to update environment variables in $env_file"
      return 1
    fi
  else
    log_debug "Environment variables already set in $env_file"
  fi

  log_info "VA-API setup completed successfully"
  log_debug "Note: You may need to reboot for changes to take effect"
  return 0
}

# TEST: Remove GNOME desktop environment while keeping NetworkManager.
# This function removes common GNOME packages. It is experimental.
#WARN: Make sure this won't delete NetworkManager
#NOTE: Do not include this all_option
remove_gnome() {
  log_info "Removing GNOME desktop environment..."

  # First check if NetworkManager is installed
  if ! rpm -q NetworkManager &>/dev/null; then
    log_error "NetworkManager is not installed"
    return 1
  fi

  # Check if GNOME is installed
  local gnome_packages=("gnome-shell" "gnome-session" "gnome-desktop")
  local any_installed=false

  for pkg in "${gnome_packages[@]}"; do
    if rpm -q "$pkg" &>/dev/null; then
      any_installed=true
      break
    fi
  done

  if [[ "$any_installed" == "false" ]]; then
    log_info "GNOME packages are not installed"
    return 0
  fi

  log_warn "This will remove GNOME desktop environment. Make sure you have another DE installed."
  read -p "Do you want to continue? [y/N] " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "GNOME removal cancelled by user"
    return 0
  fi

  log_debug "Removing GNOME packages..."
  if ! sudo dnf remove -y "${gnome_packages[@]}"; then
    log_error "Failed to remove GNOME packages"
    return 1
  fi

  # Verify NetworkManager is still installed
  if ! rpm -q NetworkManager &>/dev/null; then
    log_error "NetworkManager was removed during GNOME removal!"
    log_error "Please reinstall NetworkManager immediately to maintain network connectivity"
    return 1
  fi

  log_info "GNOME desktop environment removed successfully"
  log_debug "NetworkManager is still installed and preserved"
  return 0
}

#TEST: Both desktop and laptop
trash_cli_setup() {
  log_info "Setting up trash-cli service..."

  local dir_trash_cli_service="/etc/systemd/system/trash-cli.service"
  local dir_trash_cli_timer="/etc/systemd/system/trash-cli.timer"
  local trash_cli_service_file="./configs/trash-cli/trash-cli.service"
  local trash_cli_timer_file="./configs/trash-cli/trash-cli.timer"
  
  # Create service file
  if ! sudo cp "$trash_cli_service_file" "$dir_trash_cli_service"; then
    log_error "Failed to copy trash-cli service file"
    return 1
  fi

  # Create timer file
  if ! sudo cp "$trash_cli_timer_file" "$dir_trash_cli_timer"; then
    log_error "Failed to copy trash-cli timer file"
    return 1
  fi

  log_info "Enabling trash-cli timer..."
  sudo systemctl daemon-reload
  sudo systemctl enable --now trash-cli.timer

  log_info "trash-cli service setup completed."
}