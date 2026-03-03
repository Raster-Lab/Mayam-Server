<!-- SPDX-License-Identifier: (see LICENSE) -->

# Mayam v1.0.0 Release Notes

**Release Date:** July 2025
**Tag:** `v1.0.0`

---

## Overview

Mayam v1.0.0 is the first public release of **Mayam** — a departmental-level
Picture Archiving and Communication System (PACS) built entirely in Swift 6.2
with strict concurrency. Targeting macOS (Apple Silicon) and Linux (x86_64,
aarch64), Mayam delivers a modern, clean-sheet PACS for clinics, medium-sized
hospitals, and veterinary practices. This release represents the culmination of
15 development milestones, each independently tested and validated.

---

## Highlights

### Core DICOM Networking

- Full **DICOM Upper Layer Protocol** implementation over Swift NIO with TLS 1.3
  support.
- **C-ECHO SCP/SCU** — verification service for connectivity testing.
- **C-STORE SCP/SCU** — receive and send DICOM objects with store-as-received
  and serve-as-stored semantics.
- **C-FIND SCP/SCU** — Patient, Study, Series, and Image-level query support.
- **C-MOVE SCP/SCU** — retrieve and route studies between DICOM nodes.
- **C-GET SCP/SCU** — pull-based retrieval for firewall-friendly environments.

### Storage & Transfer Syntaxes

- **22 Storage SOP Classes** covering all common modality types.
- **15 Transfer Syntaxes** including Implicit/Explicit VR Little/Big Endian,
  JPEG, JPEG 2000, JPEG-LS, JPEG XL, RLE, and Deflated Explicit VR.
- Image codec support via **J2KSwift** (JPEG 2000, HTJ2K), **JLSwift**
  (JPEG-LS), **JXLSwift** (JPEG XL), and **OpenJP3D** (RLE).
- Compressed copy on receipt with unified object presentation.

### DICOMweb Services

- **WADO-RS** — RESTful retrieval of DICOM objects and rendered frames.
- **QIDO-RS** — RESTful query across patients, studies, series, and instances.
- **STOW-RS** — RESTful store of DICOM objects via HTTP.
- **UPS-RS** — Unified Procedure Step over REST for worklist management.
- **WADO-URI** — Legacy web-access retrieval compatibility.

### Web Administration Console

- Responsive single-page web console with JWT authentication.
- CRUD management for DICOM nodes, storage, worklist, webhooks, and system
  settings.
- Setup wizard for guided initial configuration.

### User Management & LDAP

- Local user management with role-based access control (RBAC).
- **LDAP / Active Directory** integration for enterprise authentication.
- DICOM LDAP configuration support.

### Worklist, MPPS & Workflow

- **Modality Worklist (MWL) SCP** — provide scheduled procedure information to
  modalities.
- **Modality Performed Procedure Step (MPPS) SCP** — track procedure progress in
  real time.
- **Instance Availability Notification (IAN)** — notify downstream systems when
  studies are available, exposed as both a DICOM service and a RESTful API.
- Webhook delivery with HMAC-SHA256 signatures and configurable retry.

### HL7 & FHIR Interoperability

- **HL7 v2.x MLLP** listener via [HL7kit](https://github.com/Raster-Lab/HL7kit)
  for ADT, ORM, and ORU messages with TLS 1.3 support.
- **FHIR R4 REST** endpoints for Patient, ImagingStudy, DiagnosticReport, and
  Endpoint resources.
- Configurable message routing and transformation rules.
- ACK/NACK acknowledgement workflows.

### Hierarchical Storage Management & Backup

- **HSM** — online, near-line, and offline storage tiers with automated
  migration policies.
- **Storage Commitment** (N-ACTION/N-EVENT-REPORT) for reliable archival
  confirmation.
- Automated backup and recovery with point-in-time restore.

### Security & IHE Compliance

- **Delete Protection** and **Privacy Flags** with full audit trail at Patient,
  Accession, and Study levels.
- **IHE ATNA** audit logging with syslog export and tamper-evident local
  storage.
- **DICOM Anonymisation / Pseudonymisation** profiles (PS3.15 Annex E).
- Per-study and per-patient access control lists (ACLs).
- IHE Integration Statements for SWF, PIR, CPI, KIN, and XDS-I.b profiles.
- GDPR and HIPAA compliance configuration guides.

### Monitoring & Operations

- **Prometheus-compatible `/metrics` endpoint** — associations, latency, storage
  utilisation, error rates.
- **`/health` endpoint** for load balancer and orchestrator probes.
- Sample **Grafana dashboard** configuration.
- Graceful shutdown with in-flight association draining.
- Automated database migrations on server startup.

### Performance Optimisations

- **Zero-copy buffer** handling in the DICOM association pipeline.
- **Query plan optimiser** for C-FIND on large archives (100K+ studies).
- **Concurrent C-STORE** throughput optimised to saturate 10 Gbps on Apple
  Silicon.
- HSM near-line recall prefetch cache for reduced latency.
- Reproducible benchmark suite with stress testing.

### Database

- **PostgreSQL 18.3** as the primary metadata database.
- **SQLite** fallback for lightweight and embedded deployments.
- Sequential, transactional database migrations.

### Packaging & Deployment

- **Docker** and **Docker Compose** with multi-architecture support (amd64,
  arm64).
- **macOS DMG/PKG installer** with all dependencies bundled.
- **Homebrew formula** for macOS.
- **APT and RPM packages** for Linux.
- macOS launchd plist and Linux systemd unit files.

### Documentation

- **DICOM Conformance Statement** (PS3.2 style).
- **Administrator Guide** — installation, configuration, LDAP, backup, upgrades.
- **API Reference** — OpenAPI 3.1 specifications for Admin API and DICOMweb
  endpoints.
- **Deployment Guide** — bare-metal macOS, bare-metal Linux, Docker, Docker
  Compose.

---

## Supported Platforms

| Platform | Architecture | Notes |
|---|---|---|
| macOS 14+ (Sonoma) | Apple Silicon (arm64) | Primary development platform |
| Ubuntu 22.04+ | x86_64, aarch64 | First-class Linux support |
| Docker | linux/amd64, linux/arm64 | Multi-architecture container images |

---

## Breaking Changes

This is the initial public release of Mayam — there are no breaking changes.

---

## Known Issues

- **FHIR R4 ImagingStudy and Endpoint resources** currently use interim local
  models. These will be replaced by upstream
  [HL7kit](https://github.com/Raster-Lab/HL7kit) `FHIRkit` implementations once
  the `ImagingStudy` and `Endpoint` contributions are merged.
- **`mayam-cli`** currently supports only the `config validate` command;
  additional sub-commands are planned for future releases.

---

## Installation

For detailed installation and deployment instructions, see:

- **[Deployment Guide](docs/DEPLOYMENT_GUIDE.md)** — bare-metal macOS,
  bare-metal Linux, Docker, and Docker Compose deployment walkthroughs.
- **[Administrator Guide](docs/ADMINISTRATOR_GUIDE.md)** — configuration, LDAP
  setup, backup, and upgrade procedures.

### Quick Start (Docker)

```bash
docker pull ghcr.io/raster-lab/mayam:1.0.0
docker run -d -p 11112:11112 -p 8080:8080 -p 8081:8081 ghcr.io/raster-lab/mayam:1.0.0
```

### Quick Start (Homebrew)

```bash
brew tap raster-lab/mayam
brew install mayam
mayam-server --config /usr/local/etc/mayam/config.yaml
```

---

## Contributors

Thank you to the entire **[Raster Lab](https://github.com/Raster-Lab)** team for
designing, building, and testing Mayam from the ground up. Your dedication to
Swift-native healthcare software has made this release possible.

---

## Licence

Mayam is released under the terms described in the
[LICENSE](LICENSE) file at the root of this repository.
