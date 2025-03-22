# **⚠️ WARNING**

I AM NOT RESPONSIBLE FOR ANY DAMAGE CAUSED BY THIS SCRIPT. USE AT YOUR OWN RISK.
This script is need root privileges which can be dangerous. Please, always review the script before running it.

I am currently testing this script on Fedora 41 and I am going to make sure everything is working as expected.

# Why I wrote this script

Basically, saving time. Also, I enjoy scripting and wrote this in bash for learning purposes. I hope this script will be useful to someone. If you find it useful, please give a star.

# How to use the script

```bash
WARNING:
I AM NOT RESPONSIBLE FOR ANY DAMAGE CAUSED BY THIS SCRIPT. USE AT YOUR OWN RISK.
This script is need root privileges which can be dangerous.
Please, always review the script before running it.

NOTE: Please change the variables as your system configuration.

This scripts automates the installation and configuration on Fedora Linux.


Options:
-a Execute all functions. (NOTE:System detection handled by hostname)
-b Install Brave Browser.
-B Setup borgbackup service.
-t Setup trash-cli service.
-f Setup useful linux configurations (boot timeout, tcp_bbr, terminal password timeout).
-F Install Flatpak packages.
-l Install Librewolf browser.
-L Install Lazygit.
-q Install Qtile packages.
-r Enable RPM Fusion repositories.
-d Speed up DNF (set max_parallel_downloads, pkg_gpgcheck, etc.).
-x Swap ffmpeg-free with ffmpeg.
-u Run system updates (autoremove, fwupdmgr commands).
WARNING: Below functions are need to tested with caution.
-g Remove GNOME desktop environment (keep NetworkManager).
-z Setup zenpower for Ryzen 5000 series
-n Install CUDA and NVIDIA proprietary drivers
-v Setup VA-API for NVIDIA RTX series
-p Install ProtonVPN repository and enable OpenVPN for SELinux
-o Setup Ollama.
-h Display this help message.

Example:
sudo $0 -a
```

```

```
