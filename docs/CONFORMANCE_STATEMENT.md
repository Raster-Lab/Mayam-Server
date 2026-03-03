<!-- SPDX-License-Identifier: (see LICENSE) -->

# Mayam PACS — DICOM Conformance Statement

**DICOM Standard PS3.2 — Conformance**

| | |
|---|---|
| **Product Name** | Mayam |
| **Manufacturer** | Raster Lab |
| **Product Version** | 1.0.0 |
| **DICOM Standard Version** | 2026a |
| **Document Version** | 1.0.0 |
| **Date** | 2025-07 |

---

## Table of Contents

1. [Introduction](#1-introduction)
   1. [Revision History](#11-revision-history)
   2. [Audience](#12-audience)
   3. [Remarks](#13-remarks)
   4. [Definitions and Terms](#14-definitions-and-terms)
   5. [References](#15-references)
2. [Implementation Model](#2-implementation-model)
   1. [Application Data Flow Diagram](#21-application-data-flow-diagram)
   2. [Functional Definition of AEs](#22-functional-definition-of-aes)
   3. [Sequencing of Real-World Activities](#23-sequencing-of-real-world-activities)
3. [AE Specifications](#3-ae-specifications)
   1. [MAYAM AE Specification](#31-mayam-ae-specification)
      1. [SOP Classes — Storage SCP](#311-sop-classes--storage-scp)
      2. [SOP Classes — Verification SCP/SCU](#312-sop-classes--verification-scpscu)
      3. [SOP Classes — Query/Retrieve SCP](#313-sop-classes--queryretrieve-scp)
      4. [SOP Classes — Storage SCU](#314-sop-classes--storage-scu)
      5. [SOP Classes — Modality Worklist SCP](#315-sop-classes--modality-worklist-scp)
      6. [SOP Classes — Modality Performed Procedure Step SCP](#316-sop-classes--modality-performed-procedure-step-scp)
      7. [SOP Classes — Storage Commitment SCP](#317-sop-classes--storage-commitment-scp)
      8. [SOP Classes — Instance Availability Notification SCU](#318-sop-classes--instance-availability-notification-scu)
      9. [Association Policies](#319-association-policies)
      10. [Transfer Syntaxes](#3110-transfer-syntaxes)
   2. [DICOMweb Services (PS3.18)](#32-dicomweb-services-ps318)
4. [Communication Profiles](#4-communication-profiles)
   1. [TCP/IP Stack](#41-tcpip-stack)
   2. [Physical Media Support](#42-physical-media-support)
5. [Extensions, Specialisations, and Privatisations](#5-extensions-specialisations-and-privatisations)
   1. [Standard Extended/Specialised/Private SOPs](#51-standard-extendedspecialisedprivate-sops)
   2. [Private Transfer Syntaxes](#52-private-transfer-syntaxes)
6. [Configuration](#6-configuration)
   1. [AE Title](#61-ae-title)
   2. [Networking Parameters](#62-networking-parameters)
   3. [Storage Parameters](#63-storage-parameters)
   4. [IHE Integration Profiles](#64-ihe-integration-profiles)
7. [Support of Extended Character Sets](#7-support-of-extended-character-sets)
8. [Security](#8-security)
   1. [Transport Layer Security](#81-transport-layer-security)
   2. [Audit Trail and Node Authentication (ATNA)](#82-audit-trail-and-node-authentication-atna)
   3. [Authentication and Authorisation](#83-authentication-and-authorisation)
   4. [Data Protection](#84-data-protection)
   5. [Anonymisation](#85-anonymisation)

---

## 1 Introduction

This document is the DICOM Conformance Statement for the **Mayam** Picture Archiving and Communication System (PACS) server, version 1.0.0, manufactured by **Raster Lab**. It describes the DICOM capabilities and configuration of the Mayam product in the format specified by DICOM PS3.2 (Conformance).

Mayam is a departmental-level PACS designed for clinics, hospitals, and veterinary practices. It is built entirely in Swift 6.2 with strict concurrency, targeting macOS (Apple Silicon) and Linux (x86_64, aarch64). The system implements the DICOM Standard 2026a (XML edition).

### 1.1 Revision History

| Document Version | Date | Description |
|---|---|---|
| 1.0.0 | 2025-07 | Initial conformance statement for Mayam 1.0.0 |

### 1.2 Audience

This document is intended for hospital IT administrators, clinical engineers, PACS integration specialists, and regulatory bodies who need to assess the DICOM conformance of Mayam for procurement, integration, or compliance purposes.

### 1.3 Remarks

Mayam provides both traditional DICOM network services and DICOMweb (PS3.18) RESTful services. Both interfaces share a common storage back-end and metadata database, ensuring consistent behaviour regardless of the access method used.

All configurable parameters described in this document may be adjusted via the central `mayam.yaml` configuration file or through the web-based administration console. Default values are given throughout.

### 1.4 Definitions and Terms

| Term | Definition |
|---|---|
| **AE** | Application Entity — a DICOM service end-point identified by an AE Title. |
| **AE Title** | A unique string (up to 16 characters) identifying a DICOM Application Entity. |
| **Association** | A logical DICOM connection between two AEs over which DIMSE messages are exchanged. |
| **DIMSE** | DICOM Message Service Element — the set of operations and notifications (C-STORE, C-FIND, etc.) used on an association. |
| **HSM** | Hierarchical Storage Management — automatic data lifecycle management across storage tiers. |
| **IHE** | Integrating the Healthcare Enterprise — a standards profiling initiative for health IT interoperability. |
| **MWL** | Modality Worklist — a DICOM service providing scheduled procedure information to modalities. |
| **MPPS** | Modality Performed Procedure Step — a DICOM service tracking the progress of an imaging procedure. |
| **PACS** | Picture Archiving and Communication System. |
| **PDU** | Protocol Data Unit — the fundamental transport unit in a DICOM association. |
| **Q/R** | Query/Retrieve — the DICOM query and retrieval services (C-FIND, C-MOVE, C-GET). |
| **SCP** | Service Class Provider — the DICOM role that performs an operation on behalf of a peer. |
| **SCU** | Service Class User — the DICOM role that invokes an operation on a remote peer. |
| **SOP Class** | Service-Object Pair Class — a combination of a DICOM Information Object Definition and a service. |
| **Transfer Syntax** | A set of encoding rules that specify how a DICOM data set is serialised for transmission or storage. |

### 1.5 References

- DICOM Standard 2026a — [https://www.dicomstandard.org/](https://www.dicomstandard.org/)
- DICOM PS3.2 — Conformance
- DICOM PS3.4 — Service Class Specifications
- DICOM PS3.7 — Message Exchange
- DICOM PS3.8 — Network Communication Support for Message Exchange
- DICOM PS3.15 — Security and System Management Profiles
- DICOM PS3.18 — Web Services
- IHE Technical Frameworks — [https://www.ihe.net/resources/technical_frameworks/](https://www.ihe.net/resources/technical_frameworks/)
- RFC 5424 — The Syslog Protocol
- RFC 5425 — Transport Layer Security (TLS) Transport Mapping for Syslog

---

## 2 Implementation Model

### 2.1 Application Data Flow Diagram

The following diagram illustrates the data flow between Mayam and external systems:

```
                        ┌─────────────────┐
                        │   Modalities    │
                        │ (CT, MR, US, …) │
                        └────────┬────────┘
                                 │ C-STORE, MPPS, MWL
                                 ▼
┌──────────┐           ┌─────────────────┐           ┌──────────┐
│   RIS    │◄─────────►│     Mayam       │◄─────────►│Workstation│
│  (HL7)   │  HL7/FHIR │   PACS Server   │  C-FIND   │ (Viewer) │
└──────────┘           │                 │  C-MOVE   └──────────┘
                       │  AE: MAYAM      │  C-GET
┌──────────┐           │  Port: 11112    │           ┌──────────┐
│  Syslog  │◄──────────│  Web:  8080     │──────────►│  Remote  │
│  Server  │   ATNA    │                 │  C-STORE  │   PACS   │
└──────────┘           └─────────────────┘  (forward)└──────────┘
                                 ▲
                                 │ DICOMweb (WADO/QIDO/STOW/UPS)
                                 ▼
                        ┌─────────────────┐
                        │   Web Clients   │
                        │   (Browsers)    │
                        └─────────────────┘
```

### 2.2 Functional Definition of AEs

Mayam exposes a single Application Entity, **MAYAM**, that provides all supported DICOM network services. The AE simultaneously acts as both SCP and SCU for the services described in [Section 3](#3-ae-specifications).

| Function | Description |
|---|---|
| **Storage SCP** | Receives DICOM objects from modalities, workstations, and other PACS nodes. Objects are validated, indexed in the metadata database, and persisted to the configured storage tier. |
| **Storage SCU** | Transmits DICOM objects to remote AEs in response to C-MOVE requests or routing rules. |
| **Verification SCP/SCU** | Responds to and initiates C-ECHO requests for connectivity testing. |
| **Query/Retrieve SCP** | Responds to C-FIND, C-MOVE, and C-GET requests from remote SCUs at Patient Root and Study Root levels. |
| **Modality Worklist SCP** | Provides scheduled procedure step information to modalities via C-FIND on the MWL Information Model. |
| **MPPS SCP** | Receives Modality Performed Procedure Step notifications (N-CREATE, N-SET) from modalities. |
| **Storage Commitment SCP** | Confirms reliable archival of SOP Instances via the Storage Commitment Push Model (N-ACTION, N-EVENT-REPORT). |
| **Instance Availability Notification SCU** | Notifies downstream systems (e.g., RIS, other PACS) when new instances become available. |

### 2.3 Sequencing of Real-World Activities

The typical clinical workflow involves the following sequence of interactions:

1. **Scheduling** — The RIS sends HL7 ORM messages; Mayam creates worklist entries.
2. **Modality Worklist** — The modality queries Mayam for its scheduled procedure steps (C-FIND on MWL).
3. **Acquisition** — The modality acquires images and sends an MPPS N-CREATE to Mayam.
4. **Storage** — The modality stores acquired images via C-STORE; Mayam archives and indexes them.
5. **MPPS Completion** — The modality sends an MPPS N-SET (COMPLETED or DISCONTINUED).
6. **Storage Commitment** — The modality requests storage commitment (N-ACTION); Mayam verifies archival and responds (N-EVENT-REPORT).
7. **Notification** — Mayam sends Instance Availability Notifications to configured destinations.
8. **Retrieval** — A workstation queries Mayam (C-FIND) and retrieves studies (C-MOVE/C-GET) or accesses them via DICOMweb.
9. **Routing** — Mayam forwards studies to remote nodes according to configured routing rules.

---

## 3 AE Specifications

### 3.1 MAYAM AE Specification

| Parameter | Value |
|---|---|
| **AE Title** | MAYAM (configurable) |
| **Port** | 11112 (configurable) |
| **Implementation Class UID** | 1.2.826.0.1.3680043.8.1545.1 |
| **Implementation Version Name** | MAYAM_100 |

#### 3.1.1 SOP Classes — Storage SCP

Mayam accepts and stores instances for the following Storage SOP Classes:

| SOP Class Name | SOP Class UID |
|---|---|
| CT Image Storage | 1.2.840.10008.5.1.4.1.1.2 |
| MR Image Storage | 1.2.840.10008.5.1.4.1.1.4 |
| Ultrasound Image Storage | 1.2.840.10008.5.1.4.1.1.6.1 |
| X-Ray Angiographic Image Storage | 1.2.840.10008.5.1.4.1.1.12.1 |
| Computed Radiography Image Storage | 1.2.840.10008.5.1.4.1.1.1 |
| Digital X-Ray Image Storage — For Presentation | 1.2.840.10008.5.1.4.1.1.1.1 |
| Secondary Capture Image Storage | 1.2.840.10008.5.1.4.1.1.7 |
| Nuclear Medicine Image Storage | 1.2.840.10008.5.1.4.1.1.20 |
| Positron Emission Tomography Image Storage | 1.2.840.10008.5.1.4.1.1.128 |
| Digital Mammography X-Ray Image Storage — For Presentation | 1.2.840.10008.5.1.4.1.1.1.2 |
| Intra-Oral Radiograph Image Storage — For Presentation | 1.2.840.10008.5.1.4.1.1.1.3 |
| VL Photographic Image Storage | 1.2.840.10008.5.1.4.1.1.77.1.4 |
| Segmentation Storage | 1.2.840.10008.5.1.4.1.1.66.4 |
| Key Object Selection Document Storage | 1.2.840.10008.5.1.4.1.1.88.59 |
| Grayscale Softcopy Presentation State Storage | 1.2.840.10008.5.1.4.1.1.11.1 |
| Basic Text SR Storage | 1.2.840.10008.5.1.4.1.1.88.11 |
| Enhanced SR Storage | 1.2.840.10008.5.1.4.1.1.88.22 |
| Comprehensive SR Storage | 1.2.840.10008.5.1.4.1.1.88.33 |
| RT Image Storage | 1.2.840.10008.5.1.4.1.1.481.1 |
| RT Dose Storage | 1.2.840.10008.5.1.4.1.1.481.2 |
| RT Structure Set Storage | 1.2.840.10008.5.1.4.1.1.481.3 |
| RT Plan Storage | 1.2.840.10008.5.1.4.1.1.481.5 |

**Role:** SCP (Service Class Provider)

**Behaviour:** Upon receipt of a C-STORE request, Mayam validates the DICOM data set, generates a SHA-256 checksum, indexes the object in the metadata database (Patient → Study → Series → Instance hierarchy), and persists the pixel data and attributes to the configured storage tier. Duplicate instances are detected via content-addressable hashing and de-duplicated. A C-STORE response with status `0000H` (Success) is returned upon successful archival.

#### 3.1.2 SOP Classes — Verification SCP/SCU

| SOP Class Name | SOP Class UID |
|---|---|
| Verification SOP Class | 1.2.840.10008.1.1 |

**Role:** SCP and SCU

**Behaviour:** As SCP, Mayam responds to C-ECHO requests with status `0000H` (Success). As SCU, Mayam can initiate C-ECHO requests to remote AEs for connectivity testing via the administration console or CLI.

#### 3.1.3 SOP Classes — Query/Retrieve SCP

| SOP Class Name | SOP Class UID |
|---|---|
| Patient Root Query/Retrieve Information Model — FIND | 1.2.840.10008.5.1.4.1.2.1.1 |
| Study Root Query/Retrieve Information Model — FIND | 1.2.840.10008.5.1.4.1.2.2.1 |
| Patient Root Query/Retrieve Information Model — MOVE | 1.2.840.10008.5.1.4.1.2.1.2 |
| Study Root Query/Retrieve Information Model — MOVE | 1.2.840.10008.5.1.4.1.2.2.2 |
| Patient Root Query/Retrieve Information Model — GET | 1.2.840.10008.5.1.4.1.2.1.3 |
| Study Root Query/Retrieve Information Model — GET | 1.2.840.10008.5.1.4.1.2.2.3 |

**Role:** SCP

**Supported Query Levels:**

- **Patient Level** — Patient ID, Patient Name, Patient Birth Date, Patient Sex
- **Study Level** — Study Instance UID, Study Date, Study Time, Accession Number, Study Description, Modalities in Study, Referring Physician Name, Number of Study Related Series, Number of Study Related Instances
- **Series Level** — Series Instance UID, Series Number, Modality, Series Description, Number of Series Related Instances, Body Part Examined
- **Instance Level** — SOP Instance UID, SOP Class UID, Instance Number, Rows, Columns

**C-FIND Behaviour:** Mayam matches query keys against the metadata database and returns matching records as C-FIND responses. Wildcard matching (`*`, `?`) is supported for string attributes. Date and time range matching is supported using the `-` range delimiter. Privacy-flagged entities are excluded from results unless the requesting user has explicit authorisation.

**C-MOVE Behaviour:** Mayam retrieves the requested instances from storage and transmits them to the destination AE specified in the Move Destination field. A new association is opened to the destination AE for each C-MOVE sub-operation. The response includes counts of completed, failed, and remaining sub-operations.

**C-GET Behaviour:** Mayam returns requested instances on the same association as the C-GET request. The SCU must propose the appropriate Storage SOP Classes as an SCP on the same association.

#### 3.1.4 SOP Classes — Storage SCU

Mayam acts as a Storage SCU when forwarding instances in response to C-MOVE requests or when executing routing rules. The supported Storage SOP Classes are identical to those listed in [Section 3.1.1](#311-sop-classes--storage-scp).

**Role:** SCU (Service Class User)

**Behaviour:** Mayam opens a new association to the destination AE, negotiates the appropriate SOP Class and Transfer Syntax, and transmits the requested instances via C-STORE. Transfer Syntax negotiation follows the preference order described in [Section 3.1.10](#3110-transfer-syntaxes), favouring the original stored Transfer Syntax to avoid unnecessary transcoding (serve-as-stored).

#### 3.1.5 SOP Classes — Modality Worklist SCP

| SOP Class Name | SOP Class UID |
|---|---|
| Modality Worklist Information Model — FIND | 1.2.840.10008.5.1.4.31 |

**Role:** SCP

**Behaviour:** Mayam responds to C-FIND requests on the Modality Worklist Information Model with matching scheduled procedure step records. Worklist entries are populated from HL7 ORM messages received via the integrated HL7 v2 listener, or may be created manually through the administration console or RESTful API. Returned attributes include Scheduled Procedure Step Sequence, Requested Procedure, Patient demographics, and Imaging Service Request fields.

#### 3.1.6 SOP Classes — Modality Performed Procedure Step SCP

| SOP Class Name | SOP Class UID |
|---|---|
| Modality Performed Procedure Step SOP Class | 1.2.840.10008.3.1.2.3.3 |

**Role:** SCP

**Behaviour:** Mayam accepts MPPS N-CREATE and N-SET requests from modalities. The MPPS status is tracked (IN PROGRESS, COMPLETED, DISCONTINUED) and correlated with the corresponding worklist entry. MPPS data is used to update study metadata and trigger downstream notifications. The administration console provides real-time visibility into in-progress procedures.

#### 3.1.7 SOP Classes — Storage Commitment SCP

| SOP Class Name | SOP Class UID |
|---|---|
| Storage Commitment Push Model SOP Class | 1.2.840.10008.1.20.1 |

**Role:** SCP

**Behaviour:** Mayam accepts N-ACTION requests containing a list of SOP Instance UIDs to commit. For each referenced instance, Mayam verifies that the object is archived, its SHA-256 checksum is intact, and it is stored on a durable storage tier. A corresponding N-EVENT-REPORT is returned on the same or a new association, indicating success or failure for each instance. Failed commitments include the appropriate failure reason code.

#### 3.1.8 SOP Classes — Instance Availability Notification SCU

| SOP Class Name | SOP Class UID |
|---|---|
| Instance Availability Notification SOP Class | 1.2.840.10008.5.1.4.33 |

**Role:** SCU

**Behaviour:** When new instances become available (e.g., following successful C-STORE or STOW-RS ingest), Mayam sends Instance Availability Notification messages to configured remote AEs. The notification includes the Study Instance UID, Series Instance UIDs, and SOP Instance UIDs of the newly available instances, along with their availability status. This service is also exposed as a RESTful webhook for non-DICOM consumers.

#### 3.1.9 Association Policies

##### 3.1.9.1 General

| Parameter | Value |
|---|---|
| Maximum PDU Size (receive) | 16 384 bytes (configurable) |
| Maximum PDU Size (send) | 16 384 bytes (configurable) |
| Maximum Simultaneous Associations | 64 (configurable) |
| Asynchronous Operations | Supported |
| Implementation Class UID | 1.2.826.0.1.3680043.8.1545.1 |
| Implementation Version Name | MAYAM_100 |

##### 3.1.9.2 Number of Associations

Mayam supports up to **64** concurrent DICOM associations by default. This limit is configurable and may be increased or decreased based on deployment requirements and available system resources. When the maximum number of associations is reached, incoming connection requests are rejected with an A-ASSOCIATE-RJ PDU (result = rejected-transient, source = service-provider, reason = local-limit-exceeded).

##### 3.1.9.3 Asynchronous Nature of Operations

Mayam supports the Asynchronous Operations Window Negotiation sub-item as defined in DICOM PS3.7. When the remote SCU proposes asynchronous operations, Mayam negotiates an appropriate window size. This allows multiple outstanding DIMSE operations on a single association, improving throughput for bulk transfers.

##### 3.1.9.4 Association Initiation Policy

Mayam initiates associations in the following circumstances:

- **C-MOVE forwarding** — When acting as a Q/R SCP, Mayam opens a new association to the Move Destination AE to transmit the requested instances.
- **Routing rules** — Mayam initiates associations to forward received studies to configured destination AEs based on attribute-matching rules (modality, referring physician, study description, etc.).
- **C-ECHO** — Connectivity testing initiated by an administrator via the console or CLI.
- **Instance Availability Notification** — Mayam initiates associations to notify configured remote AEs of newly available instances.
- **Storage Commitment** — When configured as an SCU, Mayam may request commitment from a remote SCP.

##### 3.1.9.5 Association Acceptance Policy

Mayam accepts associations from any remote AE whose AE Title is registered in the configuration. Unknown AEs are rejected by default; this behaviour may be changed to accept all AEs via the `dicom.acceptUnknownAEs` configuration parameter.

All accepted associations are subject to:

- AE Title validation against the configured remote AE list.
- Optional TLS mutual authentication (when TLS is enabled).
- Role-based access control, restricting which SOP Classes a given remote AE may invoke.

#### 3.1.10 Transfer Syntaxes

Mayam supports the following 15 Transfer Syntaxes for all applicable SOP Classes:

| Transfer Syntax Name | UID | Type |
|---|---|---|
| Implicit VR Little Endian | 1.2.840.10008.1.2 | Uncompressed |
| Explicit VR Little Endian | 1.2.840.10008.1.2.1 | Uncompressed |
| Explicit VR Big Endian (Retired) | 1.2.840.10008.1.2.2 | Uncompressed |
| Deflated Explicit VR Little Endian | 1.2.840.10008.1.2.1.99 | Compressed |
| RLE Lossless | 1.2.840.10008.1.2.5 | Lossless |
| JPEG-LS Lossless | 1.2.840.10008.1.2.4.80 | Lossless |
| JPEG-LS Near-Lossless | 1.2.840.10008.1.2.4.81 | Near-Lossless |
| JPEG 2000 Lossless Only | 1.2.840.10008.1.2.4.90 | Lossless |
| JPEG 2000 | 1.2.840.10008.1.2.4.91 | Lossy/Lossless |
| High-Throughput JPEG 2000 (HTJ2K) Lossless Only | 1.2.840.10008.1.2.4.201 | Lossless |
| High-Throughput JPEG 2000 (HTJ2K) | 1.2.840.10008.1.2.4.202 | Lossy/Lossless |
| High-Throughput JPEG 2000 (HTJ2K) Lossless RPCL | 1.2.840.10008.1.2.4.203 | Lossless |
| JPEG XL Lossless | 1.2.840.10008.1.2.4.110 | Lossless |
| JPEG XL Recompression | 1.2.840.10008.1.2.4.111 | Lossy/Lossless |
| Encapsulated Uncompressed Explicit VR Little Endian | 1.2.840.10008.1.2.1.98 | Uncompressed |

**Transfer Syntax Negotiation Policy:**

When acting as **SCP**, Mayam accepts any of the above Transfer Syntaxes as proposed by the SCU. The "store-as-received" policy preserves the original encoding to avoid unnecessary transcoding.

When acting as **SCU**, Mayam proposes Transfer Syntaxes in the following preference order:

1. The Transfer Syntax in which the instance is currently stored (serve-as-stored).
2. HTJ2K Lossless Only (for high-throughput lossless retrieval).
3. JPEG 2000 Lossless Only.
4. JPEG XL Lossless.
5. JPEG-LS Lossless.
6. RLE Lossless.
7. Explicit VR Little Endian.
8. Implicit VR Little Endian.

If the destination AE does not accept any lossless syntax matching the stored representation, Mayam transcodes the data on-the-fly.

### 3.2 DICOMweb Services (PS3.18)

Mayam implements the following DICOMweb services as defined in DICOM PS3.18:

| Service | HTTP Method | Path Pattern | Description |
|---|---|---|---|
| **WADO-RS** | GET | `/studies/{study}` | Retrieve all instances of a study |
| | GET | `/studies/{study}/series/{series}` | Retrieve all instances of a series |
| | GET | `/studies/{study}/series/{series}/instances/{instance}` | Retrieve a single instance |
| | GET | `.../instances/{instance}/frames/{frames}` | Retrieve specific pixel data frames |
| | GET | `.../metadata` | Retrieve DICOM JSON metadata |
| | GET | `.../rendered` | Retrieve rendered (consumer) representation |
| **QIDO-RS** | GET | `/studies` | Search for studies |
| | GET | `/studies/{study}/series` | Search for series within a study |
| | GET | `/studies/{study}/series/{series}/instances` | Search for instances within a series |
| **STOW-RS** | POST | `/studies` | Store instances (auto-assign study) |
| | POST | `/studies/{study}` | Store instances in a specific study |
| **UPS-RS** | POST | `/workitems` | Create a Unified Procedure Step |
| | GET | `/workitems` | Search for workitems |
| | GET | `/workitems/{workitem}` | Retrieve a specific workitem |
| | POST | `/workitems/{workitem}` | Update a workitem |
| | PUT | `/workitems/{workitem}/state` | Change workitem state |
| | POST | `/workitems/{workitem}/subscribers/{ae}` | Subscribe to workitem events |
| | DELETE | `/workitems/{workitem}/subscribers/{ae}` | Unsubscribe from workitem events |
| **WADO-URI** | GET | `/wado` | Legacy single-frame retrieval |

**DICOMweb Configuration:**

| Parameter | Default Value |
|---|---|
| Port | 8080 (configurable) |
| Base URL | `http://localhost:8080` (configurable) |
| TLS | Optional (TLS 1.3 when enabled) |
| Content Types | `application/dicom`, `application/dicom+json`, `application/dicom+xml`, `multipart/related` |
| Authentication | Bearer token, LDAP, or no authentication (configurable) |

**Response Media Types:**

| Resource | Supported Media Types |
|---|---|
| Instances | `application/dicom`, `multipart/related; type="application/dicom"` |
| Metadata | `application/dicom+json`, `application/dicom+xml` |
| Frames | `application/octet-stream`, `multipart/related; type="application/octet-stream"` |
| Rendered | `image/png`, `image/jpeg`, `image/gif` |
| Bulk Data | `application/octet-stream` |

---

## 4 Communication Profiles

### 4.1 TCP/IP Stack

Mayam implements the DICOM Upper Layer Protocol over TCP/IP as specified in DICOM PS3.8. The networking layer is built on **Swift NIO**, a high-performance, event-driven, non-blocking I/O framework.

| Parameter | Value |
|---|---|
| Transport Protocol | TCP/IP |
| I/O Framework | Swift NIO |
| DICOM Port (default) | 11112 |
| DICOMweb Port (default) | 8080 |
| Maximum PDU Size | 16 384 bytes (configurable) |
| TCP No-Delay | Enabled |
| Socket Keep-Alive | Enabled |
| ARTIM Timer | 30 seconds (configurable) |

**Supported Communication Profiles:**

| Profile | Description |
|---|---|
| DICOM Upper Layer for TCP/IP | Standard DICOM association over TCP (PS3.8 Annex A) |
| DICOM Web Service over HTTP | DICOMweb services (PS3.18) over HTTP/1.1 or HTTP/2 |
| DICOM Secure Transport | DICOM association secured with TLS 1.3 (PS3.15 Annex B) |
| DICOM Web Service over HTTPS | DICOMweb services over HTTPS with TLS 1.3 |

### 4.2 Physical Media Support

Mayam does not support DICOM Media Storage (PS3.10/PS3.12) as a network service. Study-level export to DICOMDIR-structured media may be performed through the administration console or CLI as an offline operation.

---

## 5 Extensions, Specialisations, and Privatisations

### 5.1 Standard Extended/Specialised/Private SOPs

Mayam does not define any private SOP Classes. All supported SOP Classes conform to their standard definitions in DICOM 2026a.

Mayam supports the following **Extended Negotiation** items:

| Item | Description |
|---|---|
| SOP Class Extended Negotiation | Relational queries supported for Patient Root and Study Root Q/R |
| SOP Class Common Extended Negotiation | Service class application information exchanged for Storage SOP Classes |

### 5.2 Private Transfer Syntaxes

Mayam does not define any private Transfer Syntaxes. All supported Transfer Syntaxes are standard DICOM Transfer Syntaxes as listed in [Section 3.1.10](#3110-transfer-syntaxes).

---

## 6 Configuration

All configuration is performed via the central `mayam.yaml` file or through the web-based administration console.

### 6.1 AE Title

| Parameter | Configuration Key | Default |
|---|---|---|
| Local AE Title | `dicom.aeTitle` | `MAYAM` |

The AE Title may be any string of up to 16 characters conforming to the DICOM AE Title character repertoire (upper-case letters, digits, space, and selected special characters). The default value is `MAYAM`.

### 6.2 Networking Parameters

| Parameter | Configuration Key | Default | Notes |
|---|---|---|---|
| DICOM Listen Port | `dicom.port` | 11112 | TCP port for DICOM associations |
| DICOMweb Listen Port | `web.port` | 8080 | TCP port for DICOMweb services |
| Admin Console Port | `admin.port` | 8081 | TCP port for the administration console |
| Maximum PDU Size | `dicom.maxPDUSize` | 16 384 | Range: 4 096 – 131 072 bytes |
| Maximum Associations | `dicom.maxAssociations` | 64 | Range: 1 – 512 |
| ARTIM Timeout | `dicom.artimTimeout` | 30 | Seconds; 0 to disable |
| Accept Unknown AEs | `dicom.acceptUnknownAEs` | false | When true, accept associations from unregistered AEs |
| TLS Enabled (DICOM) | `dicom.tlsEnabled` | false | Enable TLS 1.3 for DICOM associations |
| TLS Enabled (DICOMweb) | `web.tlsEnabled` | false | Enable TLS 1.3 for DICOMweb |
| TLS Certificate Path | `dicom.tlsCertificatePath` | — | PEM-encoded certificate file |
| TLS Key Path | `dicom.tlsKeyPath` | — | PEM-encoded private key file |

### 6.3 Storage Parameters

| Parameter | Configuration Key | Default | Notes |
|---|---|---|---|
| Storage Path | `storage.path` | `/var/lib/mayam/data` | Root directory for DICOM object storage |
| Checksum Enabled | `storage.checksumEnabled` | true | SHA-256 integrity checksums |
| De-duplication | `storage.deduplicationEnabled` | true | Content-addressable de-duplication |
| Store-As-Received | `storage.storeAsReceived` | true | Preserve original Transfer Syntax |
| HSM Enabled | `storage.hsmEnabled` | false | Enable hierarchical storage management |

### 6.4 IHE Integration Profiles

Mayam supports the following IHE Integration Profiles:

| Profile | Acronym | Actor(s) | Description |
|---|---|---|---|
| Scheduled Workflow | SWF | Image Manager/Archive, Order Filler | End-to-end imaging workflow from order to image availability. Includes MWL, MPPS, storage, and query/retrieve. |
| Patient Information Reconciliation | PIR | Image Manager/Archive | Reconciliation of patient demographics when a study is performed on an unidentified or incorrectly identified patient. |
| Consistent Presentation of Images | CPI | Image Manager/Archive | Storage and retrieval of Grayscale Softcopy Presentation States to ensure consistent image display across workstations. |
| Key Image Note | KIN | Image Manager/Archive | Storage and retrieval of Key Object Selection Documents for flagging clinically significant images. |
| Cross-Enterprise Document Sharing for Imaging | XDS-I.b | Imaging Document Source | Publication of imaging studies as XDS documents for cross-enterprise sharing via an XDS Registry/Repository. |
| Audit Trail and Node Authentication | ATNA | Secure Node | TLS-secured communication and comprehensive audit logging conforming to IHE ATNA with RFC 5424 syslog transport. |

---

## 7 Support of Extended Character Sets

Mayam supports the following DICOM Specific Character Sets:

| Character Set | DICOM Defined Term | ISO Registration | Description |
|---|---|---|---|
| Latin Alphabet No. 1 | ISO_IR 100 | ISO 8859-1 | Default character set; Western European languages |
| Unicode UTF-8 | ISO_IR 192 | ISO/IEC 10646 | Full Unicode support via UTF-8 encoding |

**Behaviour:**

- The default character set is **ISO IR 100** (Latin-1). When no Specific Character Set (0008,0005) attribute is present in a received data set, Mayam assumes ISO IR 100.
- When **ISO_IR 192** (UTF-8) is specified, Mayam stores and returns all string attributes in UTF-8 encoding.
- Mayam preserves the Specific Character Set attribute as received and applies the corresponding encoding when returning data via C-FIND, C-MOVE, C-GET, or DICOMweb services.
- The DICOMweb interface always uses UTF-8 encoding for JSON and XML responses, regardless of the stored Specific Character Set.
- The administration console displays all text attributes in UTF-8.

---

## 8 Security

### 8.1 Transport Layer Security

Mayam supports **TLS 1.3** for all network interfaces, conforming to the DICOM Secure Transport Connection Profile (PS3.15 Annex B).

| Parameter | Value |
|---|---|
| TLS Version | 1.3 |
| Cipher Suites | TLS_AES_256_GCM_SHA384, TLS_AES_128_GCM_SHA256, TLS_CHACHA20_POLY1305_SHA256 |
| Certificate Format | PEM (X.509 v3) |
| Minimum Key Length | RSA 2048-bit or ECDSA P-256 |
| Client Authentication | Optional (mutual TLS) |
| OCSP Stapling | Supported |

TLS may be enabled independently for each network interface (DICOM, DICOMweb, administration console, HL7 MLLP, syslog export). When enabled, all communication on that interface is encrypted; unencrypted connections are refused.

### 8.2 Audit Trail and Node Authentication (ATNA)

Mayam implements the IHE ATNA profile for security audit logging, conforming to RFC 3881 and the DICOM Audit Message XML schema.

**Audit Transport:**

| Transport | Standard | Port (default) |
|---|---|---|
| TLS-secured TCP | RFC 5425 | 6514 |
| Plain TCP | RFC 6587 | 601 |
| UDP | RFC 5426 | 514 |

**Audited Events:**

| Event ID | Code | Description |
|---|---|---|
| Application Activity | 110100 | Server start and stop |
| Audit Log Used | 110101 | Audit log accessed or exported |
| DICOM Instances Accessed | 110103 | Study, series, or instance viewed/retrieved |
| DICOM Instances Transferred | 110104 | C-STORE, C-MOVE, C-GET, STOW-RS |
| DICOM Study Deleted | 110105 | Study permanently removed |
| Export | 110106 | Data exported (anonymised or identifiable) |
| Import | 110107 | Data imported via C-STORE or STOW-RS |
| Order Record | 110109 | Worklist order created, modified, or cancelled |
| Patient Record | 110110 | Patient demographics created, modified, or merged |
| Query | 110112 | C-FIND, QIDO-RS query executed |
| Security Alert | 110113 | Unauthorised access, failed authentication, policy violation |
| User Authentication | 110114 | Login, logout, session timeout |

All audit messages include:

- Timestamp (UTC)
- Event outcome (success, minor failure, serious failure, major failure)
- Active participant identification (user, process, AE Title)
- Audit source identification
- Participant object identification (patient, study, SOP Instance)

Audit messages are stored locally with **HMAC-SHA256** tamper-evident integrity protection and may be exported to a remote syslog server for centralised collection.

### 8.3 Authentication and Authorisation

**Authentication Methods:**

| Method | Description |
|---|---|
| LDAP / Active Directory | Integration with enterprise directory services for user authentication |
| Local Accounts | Built-in user database for standalone deployments |
| Bearer Token (OAuth 2.0) | Token-based authentication for DICOMweb clients |
| TLS Client Certificate | Mutual TLS for DICOM node authentication |

**Role-Based Access Control (RBAC):**

| Role | Permissions |
|---|---|
| Administrator | Full system access, including configuration, user management, and protection flag changes |
| Technologist | Node management, study routing, worklist management, limited configuration |
| Physician | Query, retrieve, DICOMweb access, read-only administration |
| Auditor | Audit log access and compliance reporting |

Access control is enforced at the DICOM association level (AE Title and role mapping) and at the DICOMweb request level (HTTP authentication and authorisation headers).

### 8.4 Data Protection

Mayam provides the following data protection mechanisms:

| Feature | Description |
|---|---|
| **Delete Protection** | Entity-level flag on Patient, Accession, and Study records preventing deletion until explicitly removed by an authorised administrator. All flag changes are recorded in the `protection_flag_audit` table. |
| **Privacy Flag** | Entity-level flag restricting query visibility and retrieval access. Flagged entities are suppressed from C-FIND and QIDO-RS results and rejected from C-MOVE, C-GET, and WADO-RS retrieval unless the requesting user has explicit authorisation. |
| **SHA-256 Integrity Checksums** | Every stored DICOM object is verified against its SHA-256 checksum on retrieval to detect corruption or tampering. |
| **Encrypted Backups** | Backup archives may be encrypted using AES-256-GCM. |

### 8.5 Anonymisation

Mayam supports DICOM PS3.15 Annex E anonymisation profiles for research data export and privacy compliance:

| Profile | Description |
|---|---|
| Basic Profile | Removes or replaces all identifying attributes |
| Retain Safe Private | Preserves reviewed-safe private attributes |
| Retain UIDs | Preserves original UIDs for referential integrity |
| Retain Device Identity | Preserves station names and serial numbers |
| Retain Patient Characteristics | Preserves age, sex, size, and weight |
| Retain Long Full Dates | Preserves all date and time attributes |
| Clean Descriptors | Removes free-text description fields |

Anonymisation may be applied:

- On export (manual or automated)
- Via the DICOMweb interface (with appropriate query parameters)
- Through the administration console or CLI
- As part of routing rules (anonymise-on-forward)

All anonymisation operations are audit-logged with the original and anonymised identifiers.

---

*This document is the official DICOM Conformance Statement for Mayam version 1.0.0. For the latest version of this document and additional technical documentation, refer to the Mayam project repository maintained by Raster Lab.*
