// SPDX-License-Identifier: (see LICENSE)
// Mayam Server — Configuration Model

import Foundation

/// Top-level server configuration loaded from a YAML file with optional
/// environment variable overrides.
///
/// The configuration defines all tuneable parameters for the Mayam PACS server,
/// organised by subsystem.
public struct ServerConfiguration: Sendable, Equatable {

    // MARK: - Nested Types

    /// DICOM network configuration.
    public struct DICOM: Sendable, Equatable {
        /// The Application Entity Title advertised by this server.
        public var aeTitle: String

        /// TCP port for inbound DICOM associations.
        public var port: Int

        /// Maximum number of concurrent associations.
        public var maxAssociations: Int

        public init(
            aeTitle: String = "MAYAM",
            port: Int = 11112,
            maxAssociations: Int = 64
        ) {
            self.aeTitle = aeTitle
            self.port = port
            self.maxAssociations = maxAssociations
        }
    }

    /// Storage subsystem configuration.
    public struct Storage: Sendable, Equatable {
        /// Root directory for the DICOM object archive.
        public var archivePath: String

        /// Whether to enable SHA-256 integrity checksums on ingest.
        public var checksumEnabled: Bool

        public init(
            archivePath: String = "/var/lib/mayam/archive",
            checksumEnabled: Bool = true
        ) {
            self.archivePath = archivePath
            self.checksumEnabled = checksumEnabled
        }
    }

    /// Logging configuration.
    public struct Log: Sendable, Equatable {
        /// Minimum log level (`trace`, `debug`, `info`, `notice`, `warning`, `error`, `critical`).
        public var level: String

        public init(level: String = "info") {
            self.level = level
        }
    }

    // MARK: - Stored Properties

    /// DICOM network settings.
    public var dicom: DICOM

    /// Storage settings.
    public var storage: Storage

    /// Logging settings.
    public var log: Log

    // MARK: - Initialiser

    public init(
        dicom: DICOM = DICOM(),
        storage: Storage = Storage(),
        log: Log = Log()
    ) {
        self.dicom = dicom
        self.storage = storage
        self.log = log
    }
}

// MARK: - Codable Conformance with Defaults

extension ServerConfiguration: Codable {
    enum CodingKeys: String, CodingKey {
        case dicom, storage, log
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.dicom = try container.decodeIfPresent(DICOM.self, forKey: .dicom) ?? DICOM()
        self.storage = try container.decodeIfPresent(Storage.self, forKey: .storage) ?? Storage()
        self.log = try container.decodeIfPresent(Log.self, forKey: .log) ?? Log()
    }
}

extension ServerConfiguration.DICOM: Codable {
    enum CodingKeys: String, CodingKey {
        case aeTitle, port, maxAssociations
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.aeTitle = try container.decodeIfPresent(String.self, forKey: .aeTitle) ?? "MAYAM"
        self.port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 11112
        self.maxAssociations = try container.decodeIfPresent(Int.self, forKey: .maxAssociations) ?? 64
    }
}

extension ServerConfiguration.Storage: Codable {
    enum CodingKeys: String, CodingKey {
        case archivePath, checksumEnabled
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.archivePath = try container.decodeIfPresent(String.self, forKey: .archivePath) ?? "/var/lib/mayam/archive"
        self.checksumEnabled = try container.decodeIfPresent(Bool.self, forKey: .checksumEnabled) ?? true
    }
}

extension ServerConfiguration.Log: Codable {
    enum CodingKeys: String, CodingKey {
        case level
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.level = try container.decodeIfPresent(String.self, forKey: .level) ?? "info"
    }
}
