# Fedora Podman Test Environment

This directory contains a Podman compose setup for running a Fedora container with pre-installed packages and sudo privileges.

## User Authentication

The container is configured with a user named `podman-fedora` with the following credentials:

- Username: `podman-fedora`
- Password: `fedoratest`

The user has sudo privileges and can run commands with elevated permissions by entering the password.

## Included Packages

The container comes with these basic packages pre-installed:

- git
- vim
- curl
- wget
- bash-completion
- tmux
- findutils
- procps-ng
- less
- which
- sudo

## Usage

### Building and Starting the container

```bash
# Navigate to the directory containing the compose file and Dockerfile
cd tests/

# Build and start the container in detached mode
podman-compose -f fedora-compose.yml up -d --build
```

### Accessing the container

To access the running container as the user `podman-fedora`:

```bash
# Execute a shell in the container
podman exec -it podman-fedora bash
```

### Using sudo privileges

Once inside the container, you can use sudo with the configured password:

```bash
sudo dnf install -y <package-name>
# Enter password: fedoratest when prompted
```

### Stopping the container

```bash
# Stop and remove the container
podman-compose -f fedora-compose.yml down
```

## Data Persistence

The container mounts the local `./data` directory to `/home/podman-fedora/data` inside the container for data persistence.
