# Mayam Server

**A modern, clean-sheet PACS server built from the ground up in Swift.**

Mayam Server is a departmental-level Picture Archiving and Communication System (PACS) designed for clinics, medium-sized hospitals, and veterinary practices. It is built entirely in Swift 6.2 with strict concurrency, optimised for Apple Silicon (M-series) processors, and fully cross-platform with first-class Linux support.

Mayam Server follows the **DICOM Standard 2026a** (XML edition) and leverages the [Raster-Lab](https://github.com/Raster-Lab) family of frameworks—making it both a production-grade PACS and a showcase for these libraries.

---

## Design Principles

| Principle | Description |
|---|---|
| **Clean-Sheet** | No legacy code, no C/C++ bridges for core logic—pure Swift from networking to storage. |
| **Easy to Deploy** | Single-binary server; minimal external dependencies; guided setup wizard. |
| **Easy to Administer** | Responsive web-based administration console usable by clinicians and lay staff. |
| **Stable & Performant** | Designed around Swift structured concurrency, zero-copy I/O, and Apple Silicon SIMD. |
| **Standards-First** | DICOM 2026a compliance throughout; HL7 v2/FHIR interoperability out of the box. |
| **Open & Extensible** | Clear API separation between server core and administration UI; plugin architecture. |

---

## Feature List

### Core DICOM Services

- **C-STORE SCP/SCU** — Receive and send DICOM objects from/to any modality or workstation.
- **C-FIND SCP/SCU** — Patient, Study, Series, and Image-level query support.
- **C-MOVE SCP/SCU** — Retrieve and route studies between DICOM nodes.
- **C-GET SCP/SCU** — Pull-based retrieval for firewall-friendly environments.
- **C-ECHO SCP/SCU** — DICOM verification (ping) for connectivity testing.
- **Storage Commitment (N-ACTION/N-EVENT-REPORT)** — Confirm reliable archival of studies.
- **Modality Worklist (MWL) SCP** — Provide scheduled procedure information to modalities.
- **Modality Performed Procedure Step (MPPS) SCP** — Track procedure progress in real time.
- **DICOM Print Management SCP** — Film-based and virtual print support.
- **Instance Availability Notification** — Notify downstream systems when studies are available.
- **Multiple Transfer Syntax Support** — Including Implicit/Explicit VR Little/Big Endian, JPEG, JPEG 2000, JPEG-LS, JPEG XL, RLE, and Deflated Explicit VR.

### DICOMweb Services

- **WADO-RS** — RESTful retrieval of DICOM objects and rendered frames.
- **QIDO-RS** — RESTful query across patients, studies, series, and instances.
- **STOW-RS** — RESTful store of DICOM objects via HTTP.
- **UPS-RS** — Unified Procedure Step over REST for worklist management.
- **WADO-URI** — Legacy web-access retrieval compatibility.

### Storage & Archive

- **Online Storage** — High-performance primary storage on local SSDs/NVMe with configurable file system layouts.
- **Near-Line Storage** — Tiered storage with policy-driven migration to slower/cheaper media (NAS, external drives, object storage).
- **Hierarchical Storage Management (HSM)** — Automatic data lifecycle policies (hot → warm → cold).
- **Backup & Disaster Recovery** — Scheduled and on-demand backups; support for local, network, and cloud backup targets; point-in-time recovery.
- **Storage Commitment Verification** — End-to-end integrity checks on archived data.
- **Lossless & Lossy Transcoding** — On-the-fly or background transcoding between transfer syntaxes.
- **De-Duplication** — Content-addressable detection of duplicate SOP instances.

### Image Compression

Leveraging Raster-Lab's native Swift codecs for best-in-class performance on Apple Silicon:

| Codec | Framework | Key Benefit |
|---|---|---|
| JPEG 2000 (ISO 15444) | [J2KSwift](https://github.com/Raster-Lab/J2KSwift) | Lossless & lossy; HTJ2K high-throughput mode; JPIP streaming |
| JPEG-LS (ISO 14495) | [JLSwift](https://github.com/Raster-Lab/JLSwift) | Fast lossless/near-lossless; ARM NEON acceleration |
| JPEG XL (ISO 18181) | [JXLSwift](https://github.com/Raster-Lab/JXLSwift) | Next-gen codec; progressive decode; HDR support |
| JP3D Volumetric (ISO 15444-10) | [OpenJP3D](https://github.com/Raster-Lab/OpenJP3D) | Native 3D volume compression for CT/MR stacks |

### Healthcare Interoperability

- **HL7 v2.x Messaging** — ADT, ORM, ORU message processing via [HL7kit](https://github.com/Raster-Lab/HL7kit).
- **HL7 FHIR R4** — ImagingStudy, Patient, DiagnosticReport resource support.
- **MLLP Transport** — Standard Minimal Lower Layer Protocol with TLS.
- **IHE Profile Support** — Targets key IHE Radiology profiles:
  - Scheduled Workflow (SWF)
  - Patient Information Reconciliation (PIR)
  - Consistent Presentation of Images (CPI)
  - Key Image Note (KIN)
  - Import Reconciliation Workflow (IRWF)
  - Cross-Enterprise Document Sharing for Imaging (XDS-I.b)

### Administration & Configuration

- **Responsive Web Console** — Modern HTML5/CSS/JS administration interface; mobile-friendly.
- **RESTful Admin API** — Complete separation of UI and server; every admin function available via documented REST endpoints to enable future native GUI/App tools.
- **Setup Wizard** — Guided first-run configuration for AE Title, ports, storage paths, and network settings.
- **LDAP Integration** — User authentication and authorisation via LDAP/Active Directory, following DICOM configuration standards (LDAP DICOM schema).
- **Role-Based Access Control (RBAC)** — Predefined roles (Administrator, Technologist, Physician, Auditor) with customisable permissions.
- **Audit Logging** — DICOM/IHE ATNA-compliant audit trail; syslog export.
- **Dashboard & Monitoring** — Real-time server health, storage utilisation, association statistics, and error rate metrics.
- **DICOM Node Management** — Add, edit, verify (C-ECHO) remote AE Titles from the web console.
- **Transfer Syntax & Compression Policies** — Per-node and per-modality rules for inbound/outbound transcoding.

### Networking & Performance

- **Swift Structured Concurrency** — Actor-based isolation; no data races under strict concurrency.
- **Asynchronous I/O** — Built on Swift NIO for high-throughput, non-blocking network operations.
- **Apple Silicon Optimisation** — NEON SIMD, Accelerate framework, Metal compute shaders (macOS).
- **Linux Optimisation** — io_uring, epoll, and portable SIMD paths for Swift on Linux.
- **TLS 1.3 Support** — Secure DICOM (DICOM TLS) and HTTPS for DICOMweb / Admin API.
- **Connection Pooling** — Efficient association management for high-volume modality traffic.
- **Quality of Service (QoS)** — Configurable priority queues for STAT vs. routine studies.
- **Bandwidth Throttling** — Per-node and global rate limits to protect network resources.

### Security & Compliance

- **DICOM TLS** — Encrypted DICOM associations per DICOM PS3.15.
- **HTTPS Everywhere** — All web services served over TLS.
- **LDAP/AD Authentication** — Centralised identity management.
- **IHE ATNA Audit Trail** — Tamper-evident logging of all access and modifications.
- **Data Integrity** — SHA-256 checksums on archived objects; periodic integrity scans.
- **Access Control Lists (ACLs)** — Fine-grained per-study, per-patient access where required.
- **Anonymisation / Pseudonymisation** — Built-in DICOM tag stripping profiles for research export.
- **GDPR / HIPAA Awareness** — Configuration guides and tooling to support regulatory compliance workflows.

### Deployment & Operations

- **Single-Binary Distribution** — One executable; no JVM, no container runtime required.
- **Docker & OCI Images** — Official container images for orchestrated deployments.
- **macOS Native** — Runs as a launchd service; optional menu-bar status app.
- **Linux Systemd** — Service unit file included for production Linux deployments.
- **Configuration Profiles** — YAML-based configuration with environment variable overrides.
- **Prometheus Metrics Endpoint** — `/metrics` for integration with Grafana and alerting stacks.
- **Health Check Endpoint** — `/health` for load balancers and orchestrators.
- **Automated Database Migrations** — Schema upgrades handled transparently on server start.

---

## Technology Stack

| Layer | Technology |
|---|---|
| Language | Swift 6.2 (strict concurrency) |
| DICOM Engine | [DICOMKit](https://github.com/Raster-Lab/DICOMKit) |
| Networking | Swift NIO, Async/Await, Actors |
| Image Codecs | J2KSwift, JLSwift, JXLSwift, OpenJP3D |
| HL7 / FHIR | [HL7kit](https://github.com/Raster-Lab/HL7kit) |
| Web Framework | Hummingbird (Swift) |
| Database | SQLite (embedded) / PostgreSQL (scaled) |
| Admin UI | HTML5, CSS3, Vanilla JS (no heavy frameworks) |
| Authentication | LDAP (DICOM Configuration schema) |
| Build System | Swift Package Manager |
| Platforms | macOS (Apple Silicon primary), Linux (x86_64, aarch64) |

---

## Target Audience

- **Radiology Clinics** — Single-site or small multi-site imaging centres.
- **Medium-Sized Hospitals** — Departmental PACS for radiology, cardiology, orthopaedics.
- **Veterinary Practices** — Imaging for companion and large animal medicine.
- **Research & Teaching** — Academic institutions needing a flexible, standards-compliant archive.
- **Teleradiology** — DICOMweb-enabled remote reading workflows.

---

## Getting Started

> **Note:** Mayam Server is currently in the planning and early development phase. Build and installation instructions will be provided as the project progresses through its [milestones](milestones.md).

### Requirements

- **macOS 15+** (Sequoia) with Xcode 16.3+ / Swift 6.2, or
- **Linux** (Ubuntu 24.04 LTS / Fedora 40+) with the Swift 6.2 toolchain.
- 4 GB RAM minimum; 8 GB+ recommended.
- SSD storage recommended for the primary archive.

### Quick Start (Future)

```bash
# Clone and build
git clone https://github.com/Raster-Lab/Mayam-Server.git
cd Mayam-Server
swift build -c release

# Run with guided setup
.build/release/mayam-server --setup
```

---

## Project Structure (Planned)

```
Mayam-Server/
├── Sources/
│   ├── MayamServer/          # Main server entry point
│   ├── MayamCore/            # Core PACS engine, storage, DICOM services
│   ├── MayamWeb/             # DICOMweb & Admin REST API
│   ├── MayamAdmin/           # Web console static assets
│   └── MayamCLI/             # Command-line administration tools
├── Tests/
│   ├── MayamCoreTests/
│   ├── MayamWebTests/
│   └── IntegrationTests/
├── Config/
│   └── mayam.yaml            # Default configuration
├── Docker/
│   └── Dockerfile
├── Package.swift
├── README.md
└── milestones.md
```

---

## Related Projects

| Project | Description |
|---|---|
| [DICOMKit](https://github.com/Raster-Lab/DICOMKit) | Pure Swift DICOM library — parsing, networking, DICOMweb |
| [J2KSwift](https://github.com/Raster-Lab/J2KSwift) | JPEG 2000 codec with HTJ2K and JPIP support |
| [JLSwift](https://github.com/Raster-Lab/JLSwift) | JPEG-LS lossless/near-lossless codec |
| [JXLSwift](https://github.com/Raster-Lab/JXLSwift) | JPEG XL next-generation image codec |
| [OpenJP3D](https://github.com/Raster-Lab/OpenJP3D) | JP3D volumetric image compression |
| [HL7kit](https://github.com/Raster-Lab/HL7kit) | HL7 v2.x, v3, and FHIR R4 framework |

---

## Contributing

Contributions are welcome! Please see the [milestones](milestones.md) for the current development roadmap. Contribution guidelines will be published as the project matures.

---

## Licence

This project is licensed under the terms specified in the repository. See `LICENSE` for details.

---

*Mayam Server is a [Raster-Lab](https://github.com/Raster-Lab) project.*