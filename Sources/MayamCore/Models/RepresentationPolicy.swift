// SPDX-License-Identifier: (see LICENSE)
// Mayam — Representation Policy

import Foundation

// MARK: - ModalityCodecRule

/// Specifies the default archive codec for a DICOM modality type.
///
/// When a study from the specified modality is ingested, the server may
/// create a compressed copy using the configured codec, in addition to
/// storing the original as-received.
///
/// Reference: Milestone 4 — Representation Model (Per Modality)
public struct ModalityCodecRule: Sendable, Codable, Equatable {

    /// DICOM Modality code (e.g. `"CT"`, `"MR"`, `"CR"`, `"DX"`, `"US"`).
    public var modality: String

    /// The target transfer syntax UID for the compressed copy.
    public var targetTransferSyntaxUID: String

    /// Whether the compressed copy should be created on receipt.
    public var compressOnReceipt: Bool

    /// Creates a per-modality codec rule.
    ///
    /// - Parameters:
    ///   - modality: DICOM Modality code.
    ///   - targetTransferSyntaxUID: Target transfer syntax UID.
    ///   - compressOnReceipt: Whether to create the copy on receipt.
    public init(
        modality: String,
        targetTransferSyntaxUID: String,
        compressOnReceipt: Bool = true
    ) {
        self.modality = modality
        self.targetTransferSyntaxUID = targetTransferSyntaxUID
        self.compressOnReceipt = compressOnReceipt
    }
}

// MARK: - SiteStorageProfile

/// A site-level storage profile defining which representations to create
/// and retain.
///
/// Reference: Milestone 4 — Representation Model (Per Site)
public struct SiteStorageProfile: Sendable, Codable, Equatable {

    /// Unique identifier for this site profile.
    public var siteID: String

    /// Human-readable name of the site.
    public var siteName: String

    /// Whether to retain the original (as-received) representation.
    public var retainOriginal: Bool

    /// Additional transfer syntaxes to create as compressed copies.
    public var compressedCopySyntaxes: [String]

    /// Creates a site storage profile.
    ///
    /// - Parameters:
    ///   - siteID: Unique site identifier.
    ///   - siteName: Human-readable site name.
    ///   - retainOriginal: Whether to keep originals.
    ///   - compressedCopySyntaxes: Transfer syntax UIDs for additional copies.
    public init(
        siteID: String,
        siteName: String,
        retainOriginal: Bool = true,
        compressedCopySyntaxes: [String] = []
    ) {
        self.siteID = siteID
        self.siteName = siteName
        self.retainOriginal = retainOriginal
        self.compressedCopySyntaxes = compressedCopySyntaxes
    }
}

// MARK: - TeleRadiologyDestination

/// A tele-radiology destination with pre-built compressed copies.
///
/// Destination-specific compressed copies are created at ingest or on first
/// request, based on the codec, quality, and resolution rules defined here.
///
/// Reference: Milestone 4 — Representation Model (Per Tele-Radiology Destination)
public struct TeleRadiologyDestination: Sendable, Codable, Equatable {

    /// Unique identifier for this destination.
    public var destinationID: String

    /// The remote AE Title or endpoint.
    public var destinationAETitle: String

    /// The preferred transfer syntax UID for this destination.
    public var preferredTransferSyntaxUID: String

    /// Whether to pre-build compressed copies at ingest time (vs on first request).
    public var preBuildOnIngest: Bool

    /// Maximum bandwidth in Mbps; used for bandwidth-aware selection.
    public var bandwidthMbps: Double?

    /// Creates a tele-radiology destination.
    ///
    /// - Parameters:
    ///   - destinationID: Unique destination identifier.
    ///   - destinationAETitle: Remote AE Title.
    ///   - preferredTransferSyntaxUID: Preferred transfer syntax UID.
    ///   - preBuildOnIngest: Whether to pre-build at ingest.
    ///   - bandwidthMbps: Available bandwidth in Mbps.
    public init(
        destinationID: String,
        destinationAETitle: String,
        preferredTransferSyntaxUID: String,
        preBuildOnIngest: Bool = false,
        bandwidthMbps: Double? = nil
    ) {
        self.destinationID = destinationID
        self.destinationAETitle = destinationAETitle
        self.preferredTransferSyntaxUID = preferredTransferSyntaxUID
        self.preBuildOnIngest = preBuildOnIngest
        self.bandwidthMbps = bandwidthMbps
    }
}

// MARK: - RepresentationPolicy

/// Governs the creation and retention of derivative representations.
///
/// The representation policy aggregates per-modality, per-site, and
/// per-tele-radiology destination rules, plus a global derivative limit.
///
/// Reference: Milestone 4 — Representation Model
public struct RepresentationPolicy: Sendable, Codable, Equatable {

    /// Whether compressed-copy-on-receipt is enabled globally.
    public var compressedCopyOnReceipt: Bool

    /// The default transfer syntax UID for compressed copies when no
    /// modality-specific rule matches. Defaults to JPEG 2000 Lossless.
    public var defaultCompressedCopySyntaxUID: String

    /// Per-modality codec rules.
    public var modalityRules: [ModalityCodecRule]

    /// Site-level storage profiles.
    public var siteProfiles: [SiteStorageProfile]

    /// Tele-radiology destination profiles.
    public var teleRadiologyDestinations: [TeleRadiologyDestination]

    /// Maximum number of representations per SOP Instance (including the
    /// original). `nil` means no limit.
    ///
    /// When the limit is reached, the oldest or least-used derived
    /// representation is pruned.
    public var derivativeLimit: Int?

    // MARK: - Default Policy

    /// The default representation policy.
    ///
    /// - Compressed copy on receipt: disabled.
    /// - Default codec: JPEG 2000 Lossless.
    /// - No modality rules, site profiles, or tele-radiology destinations.
    /// - Derivative limit: 3 (original + 2 compressed copies).
    public static let `default` = RepresentationPolicy(
        compressedCopyOnReceipt: false,
        defaultCompressedCopySyntaxUID: TransferSyntaxRegistry.jpeg2000LosslessUID,
        modalityRules: [],
        siteProfiles: [],
        teleRadiologyDestinations: [],
        derivativeLimit: 3
    )

    // MARK: - Initialiser

    /// Creates a representation policy.
    ///
    /// - Parameters:
    ///   - compressedCopyOnReceipt: Whether to create compressed copies on ingest.
    ///   - defaultCompressedCopySyntaxUID: Default compressed-copy transfer syntax.
    ///   - modalityRules: Per-modality codec rules.
    ///   - siteProfiles: Site-level storage profiles.
    ///   - teleRadiologyDestinations: Tele-radiology destinations.
    ///   - derivativeLimit: Maximum representations per instance, or `nil`.
    public init(
        compressedCopyOnReceipt: Bool = false,
        defaultCompressedCopySyntaxUID: String = TransferSyntaxRegistry.jpeg2000LosslessUID,
        modalityRules: [ModalityCodecRule] = [],
        siteProfiles: [SiteStorageProfile] = [],
        teleRadiologyDestinations: [TeleRadiologyDestination] = [],
        derivativeLimit: Int? = 3
    ) {
        self.compressedCopyOnReceipt = compressedCopyOnReceipt
        self.defaultCompressedCopySyntaxUID = defaultCompressedCopySyntaxUID
        self.modalityRules = modalityRules
        self.siteProfiles = siteProfiles
        self.teleRadiologyDestinations = teleRadiologyDestinations
        self.derivativeLimit = derivativeLimit
    }

    // MARK: - Public Methods

    /// Returns the target transfer syntax UID for a compressed copy of a
    /// study from the given modality.
    ///
    /// If a modality-specific rule exists, its target is used; otherwise
    /// the default compressed copy syntax is returned.
    ///
    /// - Parameter modality: The DICOM Modality code (e.g. `"CT"`).
    /// - Returns: The target transfer syntax UID.
    public func targetSyntaxUID(for modality: String) -> String {
        if let rule = modalityRules.first(where: { $0.modality == modality }) {
            return rule.targetTransferSyntaxUID
        }
        return defaultCompressedCopySyntaxUID
    }

    /// Returns whether compressed copy on receipt is enabled for the given
    /// modality.
    ///
    /// - Parameter modality: The DICOM Modality code.
    /// - Returns: `true` if compressed copy should be created on receipt.
    public func shouldCompressOnReceipt(modality: String) -> Bool {
        guard compressedCopyOnReceipt else { return false }
        if let rule = modalityRules.first(where: { $0.modality == modality }) {
            return rule.compressOnReceipt
        }
        return compressedCopyOnReceipt
    }
}
