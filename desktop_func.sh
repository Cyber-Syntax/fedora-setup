#!/bin/bash

#TODO: Need to automate update to ollama?
install_ollama() {
  echo "Setting up Ollama..."
  curl -fsSL https://ollama.com/install.sh | sed s/--add-repo/addrepo/ | sh
  echo "Ollama setup completed."
}

#TEST: Currently only for desktop
borgbackup_setup() {
  # send sh script to /opt/borg/home-borgbackup.sh
  echo "Moving borgbackup script to /opt/borg/home-borgbackup.sh..."

  # Check directory, create if not exists
  if [[ ! -d "/opt/borg" ]]; then
    mkdir -p "/opt/borg"
  fi
  # move from ~/Documents/scripts/desktop/borg/home-borgbackup.sh
  mv "$borgbackup_script" "$move_opt_dir"

  echo "Setting up borgbackup service..."
  cat <<EOF >"$borgbackup_service"
[Unit]
Description=Home Backup using BorgBackup

[Service]
Type=oneshot
ExecStart=/opt/borg/home-borgbackup.sh
EOF

  cat <<EOF >"$borgbackup_timer"
[Unit]
Description=Timer for Home Backup using BorgBackup

[Timer]
# Schedules the backup at 10:00 every day.
OnCalendar=*-*-* 10:00:00
Persistent=true
# Note: systemd timers work with local time. To follow Europe/Istanbul time, ensure your system’s timezone is set accordingly.

[Install]
WantedBy=timers.target
EOF

  echo "Reloading systemd..."
  systemctl daemon-reload
  echo "Enabling and starting borgbackup service..."
  systemctl enable --now borgbackup-home.timer
  echo "borgbackup service setup completed."

}

# Autologin for gdm
#NOTE: currently backlog
#TODO: Need to make $USER variable
gdm_auto_login() {
  echo "Setting up autologin for GDM..."
  local gdm_custom="/etc/gdm/custom.conf"
  echo "Overwriting GDM configuration ($gdm_custom)..."
  cat <<EOF >"$gdm_custom"
[daemon]
WaylandEnable=false
DefaultSession=qtile.desktop
AutomaticLoginEnable=True
AutomaticLogin=developer
EOF
  echo "GDM autologin setup completed."
}

# TEST: Setup zenpower for Ryzen 5000 series.
# This function enables the zenpower COPR repository and installs zenpower3 and zenmonitor3.
zenpower_setup() {
  echo "Setting up zenpower for Ryzen 5000 series..."
  dnf copr enable shdwchn10/zenpower3 -y
  dnf install -y zenpower3 zenmonitor3
  # blacklisting k10temp
  echo "blacklist k10temp" >/etc/modprobe.d/zenpower.conf
  echo "Zenpower setup completed. (TEST: Check if k10temp needs to be blacklisted.)"
}

# TEST: Install CUDA
nvidia_cuda_setup() {
  # https://rpmfusion.org/Howto/CUDA#Installation
  dnf config-manager addrepo --from-repofile=https://developer.download.nvidia.com/compute/cuda/repos/fedora41/$(uname -m)/cuda-fedora41.repo
  dnf clean all
  # This nvidia-driver not found in fedora 41?
  dnf module disable nvidia-driver
  dnf config-manager setopt cuda-fedora41-$(uname -m).exclude=nvidia-driver,nvidia-modprobe,nvidia-persistenced,nvidia-settings,nvidia-libXNVCtrl,nvidia-xconfig
  dnf -y install cuda-toolkit
  #TODO: check later is below package installed or not:
  #xorg-x11-drv-nvidia-cuda-libs
}

# TEST: Switch nvidia-open
switch_nvidia_open() {
  #https://rpmfusion.org/Howto/NVIDIA?highlight=%28%5CbCategoryHowto%5Cb%29#Kernel_Open
  echo "Switching to nvidia-open drivers..."
  # dnf install akmod-nvidia-open
  # dnf swap akmod-nvidia akmod-nvidia-open
  # # build the modules
  # akmods --rebuild --force

  # Rpm package not work therefore build akmod-nvidia with open
  echo "%_with_kmod_nvidia_open 1" >/etc/rpm/macros.nvidia-kmod
  # If this still not work,add --force in the end
  akmods --kernels $(uname -r) --rebuild

  #TEST: Those are probably added default by fedora on 41
  #   local modeset="/etc/modprobe.d/nvidia-modeset.conf"
  #   cat <<EOF >"$modeset"
  # options nvidia-drm modeset=1 fbdev=1
  # EOF
  # to enable old powersave mode
  # options NVreg_PreserveVideoMemoryAllocations=0

  #Disable nonfree nvidia driver
  dnf --disablerepo rpmfusion-nonfree-nvidia-driver
  echo "Wait 10-20 minutes(being paronoid) for the nvidia-open modules to build than reboot.
  Check after reboot: modinfo nvidia | grep license
  Correct output: Dual MIT/GPL
  Also check: rpm -qa kmod-nvidia\*
  Correct output: kmod-nvidia-open-6.13.7-200.fc41.x86_64-570.124.04-1.fc41.x86_64
  "
}

# TEST: Setup VA-API for NVIDIA RTX series.
vaapi_setup() {
  echo "Setting up VA-API for NVIDIA RTX series..."
  dnf install -y meson libva-devel gstreamer1-plugins-bad-freeworld nv-codec-headers nvidia-vaapi-driver gstreamer1-plugins-bad-free-devel
  # setup vaapi for firefox
  cat <<EOF >>/etc/environment
MOZ_DISABLE_RDD_SANDBOX=1
LIBVA_DRIVER_NAME=nvidia
__GLX_VENDOR_LIBRARY_NAME=nvidia
EOF
  echo "VA-API setup completed."
}

# TEST: Remove GNOME desktop environment while keeping NetworkManager.
# This function removes common GNOME packages. It is experimental.
#WARN: Make sure this won't delete NetworkManager
#NOTE: Do not include this all_option
remove_gnome() {
  echo "Removing GNOME desktop environment..."
  # Let user confirm the removal.
  dnf remove gnome-shell gnome-session gnome-desktop
  echo "GNOME desktop environment removed. (TEST: Verify that NetworkManager is still installed.)"
}
