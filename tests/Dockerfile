FROM docker.io/library/fedora:latest

# Install basic packages including sudo
RUN dnf -y update && \
    dnf -y install \
    git \
    vim \
    curl \
    wget \
    bash-completion \
    findutils \
    procps-ng \
    sudo \
    && dnf clean all

# Create user with sudo privileges
RUN useradd -m -G wheel podman-fedora && \
    echo "podman-fedora:fedoratest" | chpasswd && \
    echo "podman-fedora ALL=(ALL) ALL" >> /etc/sudoers.d/podman-fedora

# Create data directory
RUN mkdir -p /home/podman-fedora/data && \
    chown -R podman-fedora:podman-fedora /home/podman-fedora

WORKDIR /home/podman-fedora

CMD ["sleep", "infinity"]