<!-- SPDX-License-Identifier: (see LICENSE) -->

# Mayam — Deployment Guide

> **Audience:** DevOps engineers, system administrators, and IT staff responsible
> for deploying and maintaining a Mayam PACS server in development, staging, or
> production environments.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Prerequisites](#2-prerequisites)
3. [Bare-Metal macOS](#3-bare-metal-macos)
4. [Bare-Metal Linux](#4-bare-metal-linux)
5. [Docker Deployment](#5-docker-deployment)
6. [Docker Compose Deployment](#6-docker-compose-deployment)
7. [TLS Configuration](#7-tls-configuration)
8. [Post-Deployment Checklist](#8-post-deployment-checklist)
9. [Upgrading](#9-upgrading)
10. [Rollback](#10-rollback)

---

## 1. Overview

Mayam is a departmental-level PACS (Picture Archiving and Communication System)
built entirely in Swift 6.2 with strict concurrency. It provides DICOM storage,
query/retrieve, DICOMweb access, and an administrative web console in a single
binary.

### Supported Platforms

| Platform | Architecture | Status |
|---|---|---|
| macOS | Apple Silicon (arm64) | Fully supported |
| Linux | x86_64 (amd64) | Fully supported |
| Linux | aarch64 (arm64) | Fully supported |

### Deployment Options

| Option | Best For |
|---|---|
| **Bare-metal** | Maximum performance; direct hardware access |
| **Docker** | Reproducible, isolated single-container deployment |
| **Docker Compose** | Full-stack deployment with database and monitoring |

### Default Network Ports

| Port | Protocol | Service |
|---|---|---|
| `11112` | TCP | DICOM associations (C-ECHO, C-STORE, C-FIND, C-MOVE, C-GET) |
| `8080` | HTTP/HTTPS | DICOMweb (WADO-RS, STOW-RS, QIDO-RS) and `/metrics` endpoint |
| `8081` | HTTP/HTTPS | Admin web console and REST API |

---

## 2. Prerequisites

### Hardware Requirements

| Resource | Minimum | Recommended (production) |
|---|---|---|
| CPU cores | 4 | 8+ |
| RAM | 8 GB | 16 GB+ |
| Storage | SSD recommended | NVMe SSD; capacity depends on study volume |
| Network | 1 Gbps | 10 Gbps for high-throughput environments |

### Software Requirements

| Component | Version | Notes |
|---|---|---|
| **Swift runtime** | 6.2 | Required for bare-metal only; bundled in Docker image |
| **PostgreSQL** | 18.3 | Primary metadata database |
| **SQLite** | 3.x | Lightweight alternative for small deployments |
| **Docker** | 24+ | For container deployments |
| **Docker Compose** | 2.x | For orchestrated container deployments |

### TLS Certificates

TLS is optional but **strongly recommended** for production environments. You
will need:

- A server certificate and private key (PEM format) for DICOM TLS.
- A server certificate and private key for HTTPS (DICOMweb and Admin).
- Certificates may be self-signed (development) or CA-signed (production).

---

## 3. Bare-Metal macOS

### 3.1 Install via Homebrew

The simplest way to install Mayam on macOS is via the Raster Lab Homebrew tap:

```bash
brew tap raster-lab/tap
brew install mayam
```

Homebrew installs the `mayam` binary to `/opt/homebrew/bin/mayam` (Apple
Silicon) and creates a default configuration at
`/opt/homebrew/etc/mayam/mayam.yaml`.

Verify the installation:

```bash
mayam --version
```

### 3.2 Install via PKG Installer

1. Download the latest `.dmg` file from the
   [Releases](https://github.com/Raster-Lab/Mayam/releases) page.
2. Open the `.dmg` and double-click the `.pkg` installer.
3. Follow the on-screen instructions. The installer places the binary at
   `/usr/local/bin/mayam` and the default configuration at
   `/etc/mayam/mayam.yaml`.
4. Verify:

```bash
/usr/local/bin/mayam --version
```

### 3.3 Build from Source

Ensure the Swift 6.2 toolchain is installed (via [swift.org](https://swift.org)
or Xcode 16+):

```bash
swift --version   # Confirm Swift 6.2+

git clone https://github.com/Raster-Lab/Mayam.git
cd Mayam
swift build -c release
```

The release binary is located at `.build/release/mayam`. Copy it to a location
on your `PATH`:

```bash
sudo cp .build/release/mayam /usr/local/bin/mayam
```

### 3.4 PostgreSQL Setup

Install PostgreSQL 18 via Homebrew:

```bash
brew install postgresql@18
brew services start postgresql@18
```

Create the Mayam database and user:

```bash
psql postgres <<SQL
CREATE USER mayam WITH PASSWORD 'your-secure-password';
CREATE DATABASE mayam OWNER mayam;
GRANT ALL PRIVILEGES ON DATABASE mayam TO mayam;
SQL
```

> **Note:** Replace `your-secure-password` with a strong, randomly generated
> password. Never use the default password in production.

### 3.5 Configuration

Copy the default configuration to the system-wide configuration directory:

```bash
sudo mkdir -p /etc/mayam
sudo cp Config/mayam.yaml /etc/mayam/mayam.yaml
```

Edit `/etc/mayam/mayam.yaml` to match your environment:

```yaml
dicom:
  aeTitle: "MAYAM"
  port: 11112
  maxAssociations: 64
  tlsEnabled: false
  # tlsCertificatePath: "/etc/mayam/certs/server.pem"
  # tlsKeyPath: "/etc/mayam/certs/server-key.pem"

storage:
  archivePath: "/var/lib/mayam/archive"
  checksumEnabled: true

log:
  level: "info"
```

Create the archive directory:

```bash
sudo mkdir -p /var/lib/mayam/archive
sudo chown -R $(whoami) /var/lib/mayam
```

> **Tip:** For production, create a dedicated `mayam` user and group to own the
> archive directory (see [Section 3.6](#36-launch-agent-setup)).

### 3.6 Launch Agent Setup

Mayam ships with a `launchd` property list for automatic startup on macOS.

**System-wide daemon (recommended for servers):**

```bash
sudo cp Config/com.raster-lab.mayam.plist /Library/LaunchDaemons/
sudo launchctl load /Library/LaunchDaemons/com.raster-lab.mayam.plist
```

**Per-user agent (development):**

```bash
cp Config/com.raster-lab.mayam.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.raster-lab.mayam.plist
```

Manage the service:

```bash
# Stop
sudo launchctl unload /Library/LaunchDaemons/com.raster-lab.mayam.plist

# Start
sudo launchctl load /Library/LaunchDaemons/com.raster-lab.mayam.plist

# Check status
sudo launchctl list | grep com.raster-lab.mayam
```

View logs:

```bash
tail -f /var/log/mayam/mayam.log
tail -f /var/log/mayam/mayam-error.log
```

### 3.7 Verify Installation

**Health check (DICOMweb):**

```bash
curl -s http://localhost:8080/health
# Expected: {"status":"healthy"}
```

**Admin console:**

Open `http://localhost:8081` in a web browser.

**DICOM C-ECHO (using mayam-cli):**

```bash
mayam-cli echo --host localhost --port 11112 --ae-title MAYAM
# Expected: C-ECHO successful
```

**DICOM C-ECHO (using an external tool such as dcm4che `storescu`):**

```bash
echoscu localhost 11112 -aec MAYAM
```

---

## 4. Bare-Metal Linux

### 4.1 Install via APT (Debian / Ubuntu)

Import the Raster Lab signing key and add the APT repository:

```bash
curl -fsSL https://packages.raster-lab.com/gpg \
  | sudo gpg --dearmor -o /usr/share/keyrings/raster-lab.gpg

echo "deb [signed-by=/usr/share/keyrings/raster-lab.gpg] \
  https://packages.raster-lab.com/apt stable main" \
  | sudo tee /etc/apt/sources.list.d/raster-lab.list

sudo apt update && sudo apt install mayam
```

The package installs:

- `/usr/local/bin/mayam` — server binary
- `/etc/mayam/mayam.yaml` — default configuration
- `/etc/systemd/system/mayam.service` — systemd unit
- Creates the `mayam` system user and required directories

### 4.2 Install via RPM (RHEL / Fedora)

Add the Raster Lab RPM repository and install:

```bash
sudo dnf config-manager \
  --add-repo https://packages.raster-lab.com/rpm/raster-lab.repo

sudo dnf install mayam
```

The RPM package provides the same file layout as the Debian package.

### 4.3 Build from Source

Install the Swift 6.2 toolchain:

```bash
# Download the official Swift 6.2 toolchain for Linux
wget https://download.swift.org/swift-6.2-release/ubuntu2204/swift-6.2-RELEASE/swift-6.2-RELEASE-ubuntu22.04.tar.gz
tar xzf swift-6.2-RELEASE-ubuntu22.04.tar.gz
export PATH=$(pwd)/swift-6.2-RELEASE-ubuntu22.04/usr/bin:$PATH
swift --version
```

Install build dependencies:

```bash
# Debian / Ubuntu
sudo apt install -y build-essential libicu-dev libssl-dev pkg-config

# RHEL / Fedora
sudo dnf install -y gcc-c++ libicu-devel openssl-devel pkgconfig
```

Build and install:

```bash
git clone https://github.com/Raster-Lab/Mayam.git
cd Mayam
swift build -c release
sudo cp .build/release/mayam /usr/local/bin/mayam
```

### 4.4 PostgreSQL Setup

Install PostgreSQL 18.3:

```bash
# Debian / Ubuntu (using the official PostgreSQL APT repository)
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
  > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc \
  | sudo apt-key add -
sudo apt update && sudo apt install -y postgresql-18

# RHEL / Fedora
sudo dnf install -y postgresql18-server postgresql18
sudo /usr/pgsql-18/bin/postgresql-18-setup initdb
sudo systemctl enable --now postgresql-18
```

Create the Mayam database and user:

```bash
sudo -u postgres psql <<SQL
CREATE USER mayam WITH PASSWORD 'your-secure-password';
CREATE DATABASE mayam OWNER mayam;
GRANT ALL PRIVILEGES ON DATABASE mayam TO mayam;
SQL
```

### 4.5 System User and Directories

If you installed from source (the package installers handle this automatically):

```bash
sudo useradd -r -s /usr/sbin/nologin mayam
sudo mkdir -p /var/lib/mayam/archive /etc/mayam /var/log/mayam
sudo chown -R mayam:mayam /var/lib/mayam /var/log/mayam
sudo cp Config/mayam.yaml /etc/mayam/mayam.yaml
sudo chown root:mayam /etc/mayam/mayam.yaml
sudo chmod 640 /etc/mayam/mayam.yaml
```

### 4.6 systemd Service

Copy the unit file and enable the service:

```bash
sudo cp Config/mayam.service /etc/systemd/system/mayam.service
sudo systemctl daemon-reload
sudo systemctl enable --now mayam
```

Manage the service:

```bash
sudo systemctl status mayam          # Check status
sudo systemctl restart mayam         # Restart
sudo journalctl -u mayam -f          # Follow logs
sudo journalctl -u mayam --since today  # Today's logs
```

The shipped `mayam.service` includes security hardening directives:

| Directive | Purpose |
|---|---|
| `NoNewPrivileges=true` | Prevents privilege escalation |
| `ProtectSystem=strict` | Read-only filesystem except allowed paths |
| `ProtectHome=true` | Blocks access to `/home` |
| `ReadWritePaths=` | Grants write access only to `/var/lib/mayam` and `/var/log/mayam` |
| `PrivateTmp=true` | Isolates `/tmp` |
| `LimitNOFILE=65535` | Supports many concurrent DICOM associations |

### 4.7 Firewall Configuration

**UFW (Debian / Ubuntu):**

```bash
sudo ufw allow 11112/tcp comment "Mayam DICOM"
sudo ufw allow 8080/tcp  comment "Mayam DICOMweb"
sudo ufw allow 8081/tcp  comment "Mayam Admin"
sudo ufw reload
```

**firewalld (RHEL / Fedora):**

```bash
sudo firewall-cmd --permanent --add-port=11112/tcp
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --permanent --add-port=8081/tcp
sudo firewall-cmd --reload
```

> **Security note:** In production, restrict access to port `8081` (Admin
> console) to trusted management networks only.

---

## 5. Docker Deployment

### 5.1 Quick Start

Pull and run the official image:

```bash
docker pull ghcr.io/raster-lab/mayam:1.0.0
docker run -d \
  --name mayam \
  -p 11112:11112 \
  -p 8080:8080 \
  -p 8081:8081 \
  ghcr.io/raster-lab/mayam:1.0.0
```

Verify the container is healthy:

```bash
docker ps
curl -s http://localhost:8080/health
```

> **Note:** This quick-start configuration uses SQLite as the metadata store.
> For production use, configure PostgreSQL (see
> [Section 6](#6-docker-compose-deployment)).

### 5.2 Persistent Storage

Mount host directories or named volumes to preserve data across container
restarts:

```bash
docker run -d \
  --name mayam \
  -p 11112:11112 \
  -p 8080:8080 \
  -p 8081:8081 \
  -v mayam-archive:/var/lib/mayam/archive \
  -v /path/to/your/mayam.yaml:/etc/mayam/mayam.yaml:ro \
  ghcr.io/raster-lab/mayam:1.0.0
```

| Mount Point | Purpose |
|---|---|
| `/var/lib/mayam/archive` | DICOM object storage (studies, series, instances) |
| `/etc/mayam/mayam.yaml` | Configuration file (mount read-only) |
| `/etc/mayam/certs/` | TLS certificates (if TLS is enabled) |

### 5.3 Building the Image

Build the Docker image locally from the repository root:

```bash
docker build -t mayam:latest .
```

For multi-platform builds (amd64 and arm64):

```bash
docker buildx create --use
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t ghcr.io/raster-lab/mayam:latest \
  --push .
```

The `Dockerfile` uses a multi-stage build:

1. **Builder stage** — Compiles the Swift binary with a statically linked
   standard library.
2. **Runtime stage** — Minimal Ubuntu 22.04 image with only the necessary
   runtime dependencies. Runs as a non-root `mayam` user.

### 5.4 Environment Variable Configuration

All configuration values can be overridden via environment variables, which take
precedence over `mayam.yaml`:

| Variable | Default | Description |
|---|---|---|
| `MAYAM_CONFIG` | `/etc/mayam/mayam.yaml` | Path to the YAML configuration file |
| `MAYAM_DICOM_AE_TITLE` | `MAYAM` | DICOM Application Entity title |
| `MAYAM_DICOM_PORT` | `11112` | DICOM association listener port |
| `MAYAM_DICOM_MAX_ASSOCIATIONS` | `64` | Maximum concurrent DICOM associations |
| `MAYAM_DICOM_TLS_ENABLED` | `false` | Enable DICOM TLS |
| `MAYAM_DICOM_TLS_CERT_PATH` | — | Path to TLS certificate (PEM) |
| `MAYAM_DICOM_TLS_KEY_PATH` | — | Path to TLS private key (PEM) |
| `MAYAM_STORAGE_ARCHIVE_PATH` | `/var/lib/mayam/archive` | DICOM archive directory |
| `MAYAM_STORAGE_CHECKSUM_ENABLED` | `true` | Verify storage integrity checksums |
| `MAYAM_LOG_LEVEL` | `info` | Log level (`trace`, `debug`, `info`, `warning`, `error`) |
| `MAYAM_ADMIN_JWT_SECRET` | — | JWT signing secret for Admin API authentication |

Example:

```bash
docker run -d \
  --name mayam \
  -e MAYAM_DICOM_AE_TITLE=HOSPITAL_PACS \
  -e MAYAM_DICOM_MAX_ASSOCIATIONS=128 \
  -e MAYAM_LOG_LEVEL=debug \
  -e MAYAM_ADMIN_JWT_SECRET=my-secure-jwt-secret \
  -p 11112:11112 \
  -p 8080:8080 \
  -p 8081:8081 \
  -v mayam-archive:/var/lib/mayam/archive \
  ghcr.io/raster-lab/mayam:1.0.0
```

---

## 6. Docker Compose Deployment

### 6.1 Full Stack

The repository includes a `docker-compose.yml` that orchestrates Mayam with
PostgreSQL and optional monitoring (Prometheus + Grafana).

**Core services (Mayam + PostgreSQL):**

```bash
cd /path/to/Mayam
docker compose up -d
```

**With monitoring (Prometheus + Grafana):**

```bash
docker compose --profile monitoring up -d
```

**View logs:**

```bash
docker compose logs -f mayam
docker compose logs -f postgres
```

**Stop all services:**

```bash
docker compose down
```

**Stop and remove volumes (destroys data):**

```bash
docker compose down -v
```

#### Environment Variables

Create a `.env` file in the project root to customise deployment:

```bash
# .env
POSTGRES_PASSWORD=a-very-strong-database-password
MAYAM_ADMIN_JWT_SECRET=a-very-strong-jwt-secret
GRAFANA_PASSWORD=your-grafana-admin-password
```

> **Important:** Never commit the `.env` file to version control.

### 6.2 Service Details

#### PostgreSQL

| Setting | Value |
|---|---|
| Image | `postgres:18` |
| Port | `5432` |
| Database | `mayam` |
| User | `mayam` |
| Volume | `postgres_data` → `/var/lib/postgresql/data` |
| Healthcheck | `pg_isready -U mayam` (every 10 s, 5 retries) |
| Restart policy | `unless-stopped` |

#### Mayam

| Setting | Value |
|---|---|
| Build context | `.` (repository root) |
| Ports | `11112`, `8080`, `8081` |
| Depends on | PostgreSQL (`service_healthy`) |
| Volumes | `archive_data` → `/var/lib/mayam/archive`; `Config/mayam.yaml` → `/etc/mayam/mayam.yaml` (read-only) |
| Healthcheck | `curl -f http://localhost:8080/health` (every 30 s, 3 retries, 10 s start period) |
| Restart policy | `unless-stopped` |

#### Prometheus (optional — `monitoring` profile)

| Setting | Value |
|---|---|
| Image | `prom/prometheus:latest` |
| Port | `9090` |
| Config | `Config/prometheus.yml` → `/etc/prometheus/prometheus.yml` (read-only) |
| Volume | `prometheus_data` → `/prometheus` |
| Scrape target | `mayam:8080/metrics` every 15 s |

#### Grafana (optional — `monitoring` profile)

| Setting | Value |
|---|---|
| Image | `grafana/grafana:latest` |
| Port | `3000` |
| Default credentials | `admin` / `admin` (override via `GRAFANA_PASSWORD`) |
| Dashboard | `Config/grafana-dashboard.json` pre-loaded |
| Volume | `grafana_data` → `/var/lib/grafana` |
| Depends on | Prometheus |

Access the monitoring stack:

- **Prometheus:** `http://localhost:9090`
- **Grafana:** `http://localhost:3000` (default login: `admin` / `admin`)

### 6.3 Scaling Considerations

For high-availability or high-throughput environments, consider the following:

- **Database read replicas:** Configure PostgreSQL streaming replication to
  offload read queries (QIDO-RS, C-FIND) to replicas.
- **Load balancing:** Place an nginx or HAProxy reverse proxy in front of
  multiple Mayam instances for HTTP traffic (DICOMweb, Admin). DICOM
  associations are stateful — use sticky sessions or dedicated instances per
  modality.
- **Shared storage:** When running multiple Mayam instances, the archive
  directory must reside on a shared filesystem (NFS, GlusterFS, or cloud block
  storage) accessible to all instances.
- **Connection pooling:** Use PgBouncer between Mayam instances and PostgreSQL
  to manage database connections efficiently.

---

## 7. TLS Configuration

### 7.1 Generating Self-Signed Certificates (Development)

Generate a self-signed certificate and private key for development and testing:

```bash
sudo mkdir -p /etc/mayam/certs

openssl req -x509 -newkey rsa:4096 \
  -keyout /etc/mayam/certs/server-key.pem \
  -out /etc/mayam/certs/server.pem \
  -days 365 -nodes \
  -subj "/CN=mayam.local/O=Development"

sudo chown mayam:mayam /etc/mayam/certs/*
sudo chmod 600 /etc/mayam/certs/server-key.pem
sudo chmod 644 /etc/mayam/certs/server.pem
```

> **Warning:** Self-signed certificates must not be used in production.

### 7.2 Using Let's Encrypt (Production)

Use [Certbot](https://certbot.eff.org/) to obtain free, trusted TLS
certificates:

```bash
sudo apt install -y certbot

sudo certbot certonly --standalone \
  -d pacs.example.com \
  --agree-tos \
  --email admin@example.com
```

Certificates are placed in `/etc/letsencrypt/live/pacs.example.com/`. Create
symbolic links for Mayam:

```bash
sudo ln -sf /etc/letsencrypt/live/pacs.example.com/fullchain.pem \
  /etc/mayam/certs/server.pem
sudo ln -sf /etc/letsencrypt/live/pacs.example.com/privkey.pem \
  /etc/mayam/certs/server-key.pem
```

Set up automatic renewal:

```bash
sudo systemctl enable --now certbot.timer
```

Add a post-renewal hook to restart Mayam:

```bash
sudo tee /etc/letsencrypt/renewal-hooks/post/restart-mayam.sh <<'EOF'
#!/bin/bash
systemctl restart mayam
EOF
sudo chmod +x /etc/letsencrypt/renewal-hooks/post/restart-mayam.sh
```

### 7.3 Configuring DICOM TLS

Enable TLS for DICOM associations in `/etc/mayam/mayam.yaml`:

```yaml
dicom:
  aeTitle: "MAYAM"
  port: 11112
  maxAssociations: 64
  tlsEnabled: true
  tlsCertificatePath: "/etc/mayam/certs/server.pem"
  tlsKeyPath: "/etc/mayam/certs/server-key.pem"
```

Or via environment variables:

```bash
MAYAM_DICOM_TLS_ENABLED=true
MAYAM_DICOM_TLS_CERT_PATH=/etc/mayam/certs/server.pem
MAYAM_DICOM_TLS_KEY_PATH=/etc/mayam/certs/server-key.pem
```

Restart the service after making changes:

```bash
# systemd
sudo systemctl restart mayam

# launchd (macOS)
sudo launchctl unload /Library/LaunchDaemons/com.raster-lab.mayam.plist
sudo launchctl load /Library/LaunchDaemons/com.raster-lab.mayam.plist
```

### 7.4 Configuring HTTPS for DICOMweb and Admin

To secure the DICOMweb (port 8080) and Admin (port 8081) endpoints with HTTPS,
place a reverse proxy (nginx, Caddy, or HAProxy) in front of Mayam.

**Example nginx configuration:**

```nginx
server {
    listen 443 ssl http2;
    server_name pacs.example.com;

    ssl_certificate     /etc/mayam/certs/server.pem;
    ssl_certificate_key /etc/mayam/certs/server-key.pem;
    ssl_protocols       TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    # DICOMweb
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Admin console
    location /admin/ {
        proxy_pass http://127.0.0.1:8081/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

server {
    listen 80;
    server_name pacs.example.com;
    return 301 https://$host$request_uri;
}
```

---

## 8. Post-Deployment Checklist

Complete the following tasks after deploying Mayam to ensure a secure and
reliable installation:

- [ ] **Change the default admin password.** Log in to the Admin console at
      `http://localhost:8081` and update the administrator credentials
      immediately.
- [ ] **Set a strong JWT secret.** Replace the default `MAYAM_ADMIN_JWT_SECRET`
      value with a cryptographically random string (minimum 32 characters).
- [ ] **Enable TLS.** Configure DICOM TLS and HTTPS for all network
      communication (see [Section 7](#7-tls-configuration)).
- [ ] **Set up a backup schedule.** Implement regular backups for both the
      PostgreSQL database and the DICOM archive directory. Example:
      ```bash
      pg_dump -U mayam mayam | gzip > /backup/mayam-db-$(date +%F).sql.gz
      rsync -a /var/lib/mayam/archive/ /backup/mayam-archive/
      ```
- [ ] **Enable ATNA audit logging.** Configure the ATNA (Audit Trail and Node
      Authentication) syslog target in `mayam.yaml` to comply with IHE audit
      requirements.
- [ ] **Configure LDAP (optional).** If your organisation uses directory-based
      authentication, configure the LDAP connection settings in `mayam.yaml`.
- [ ] **Set up monitoring.** Deploy Prometheus and Grafana using the Docker
      Compose monitoring profile or point your existing Prometheus instance at
      `http://<mayam-host>:8080/metrics`.
- [ ] **Verify DICOM connectivity.** Send a C-ECHO from every modality and
      workstation that will communicate with Mayam:
      ```bash
      mayam-cli echo --host <mayam-host> --port 11112 --ae-title MAYAM
      ```
- [ ] **Test DICOMweb endpoints.** Confirm WADO-RS, STOW-RS, and QIDO-RS are
      operational:
      ```bash
      # QIDO-RS — list studies
      curl -s http://localhost:8080/dicomweb/studies | head -c 200

      # Health endpoint
      curl -s http://localhost:8080/health
      ```
- [ ] **Restrict network access.** Ensure the Admin console (port 8081) is only
      accessible from trusted management networks. Consider placing DICOMweb
      behind a VPN or firewall.
- [ ] **Review resource limits.** Confirm `LimitNOFILE` and `LimitNPROC` values
      in the systemd unit or launchd plist are sufficient for your expected
      workload.

---

## 9. Upgrading

### 9.1 Docker Upgrade

```bash
# Pull the new image
docker pull ghcr.io/raster-lab/mayam:<new-version>

# Stop and remove the existing container
docker stop mayam && docker rm mayam

# Start with the new image (persistent volumes are retained)
docker run -d \
  --name mayam \
  -p 11112:11112 \
  -p 8080:8080 \
  -p 8081:8081 \
  -v mayam-archive:/var/lib/mayam/archive \
  -v /path/to/mayam.yaml:/etc/mayam/mayam.yaml:ro \
  ghcr.io/raster-lab/mayam:<new-version>
```

For Docker Compose:

```bash
# Update the image tag in docker-compose.yml, then:
docker compose pull
docker compose up -d
```

### 9.2 Bare-Metal Upgrade

```bash
# 1. Stop the service
sudo systemctl stop mayam        # Linux
# or
sudo launchctl unload /Library/LaunchDaemons/com.raster-lab.mayam.plist  # macOS

# 2. Back up the current binary
sudo cp /usr/local/bin/mayam /usr/local/bin/mayam.bak

# 3. Install the new binary
# Via package manager:
sudo apt update && sudo apt upgrade mayam    # Debian / Ubuntu
sudo dnf update mayam                        # RHEL / Fedora
brew upgrade mayam                           # macOS Homebrew

# Or from source:
cd Mayam && git pull && swift build -c release
sudo cp .build/release/mayam /usr/local/bin/mayam

# 4. Start the service
sudo systemctl start mayam       # Linux
# or
sudo launchctl load /Library/LaunchDaemons/com.raster-lab.mayam.plist  # macOS
```

### 9.3 Database Migrations

Database schema migrations run **automatically** when Mayam starts. No manual
intervention is required. Migration files are located in
`Sources/MayamCore/Database/Migrations/` and are applied sequentially.

> **Tip:** Always back up the database before upgrading:
> ```bash
> pg_dump -U mayam mayam > mayam-pre-upgrade-$(date +%F).sql
> ```

---

## 10. Rollback

If an upgrade introduces issues, you can roll back to the previous version.

### 10.1 Docker Rollback

```bash
# Stop the current container
docker stop mayam && docker rm mayam

# Start with the previous image tag
docker run -d \
  --name mayam \
  -p 11112:11112 \
  -p 8080:8080 \
  -p 8081:8081 \
  -v mayam-archive:/var/lib/mayam/archive \
  -v /path/to/mayam.yaml:/etc/mayam/mayam.yaml:ro \
  ghcr.io/raster-lab/mayam:<previous-version>
```

### 10.2 Bare-Metal Rollback

```bash
# 1. Stop the service
sudo systemctl stop mayam

# 2. Restore the previous binary
sudo cp /usr/local/bin/mayam.bak /usr/local/bin/mayam

# 3. Start the service
sudo systemctl start mayam
```

### 10.3 Database Migration Compatibility

Mayam database migrations are designed to be **forward-compatible**: minor
version upgrades add columns or tables but do not remove existing structures.
This means the previous binary version can typically operate against a database
that has been migrated forward by one minor version.

However, if a **major version** upgrade includes destructive migrations
(dropping columns or tables), rolling back requires restoring the database from
a pre-upgrade backup:

```bash
# Restore from backup
sudo systemctl stop mayam
sudo -u postgres dropdb mayam
sudo -u postgres createdb -O mayam mayam
psql -U mayam mayam < mayam-pre-upgrade-YYYY-MM-DD.sql
sudo systemctl start mayam
```

> **Best practice:** Always create a database backup before any upgrade. Keep at
> least the two most recent backups readily available for rollback.
