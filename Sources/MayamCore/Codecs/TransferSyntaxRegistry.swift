// SPDX-License-Identifier: (see LICENSE)
// Mayam — Transfer Syntax Registry

import Foundation
import DICOMNetwork

// MARK: - TransferSyntaxInfo

/// Describes a DICOM Transfer Syntax and its associated codec capabilities.
///
/// Each entry in the ``TransferSyntaxRegistry`` maps a DICOM Transfer Syntax UID
/// to its human-readable name, compression characteristics, and the codec
/// framework responsible for encoding/decoding.
///
/// Reference: DICOM PS3.5 Section 10 — Transfer Syntax
public struct TransferSyntaxInfo: Sendable, Equatable {

    /// The DICOM Transfer Syntax UID (e.g. `"1.2.840.10008.1.2.4.90"`).
    public let uid: String

    /// Human-readable name of the transfer syntax.
    public let name: String

    /// Whether this transfer syntax uses compression.
    public let isCompressed: Bool

    /// Whether this transfer syntax preserves data losslessly.
    public let isLossless: Bool

    /// The codec framework used for this transfer syntax, or `nil` for
    /// uncompressed syntaxes that require no codec.
    public let codec: CodecFramework?

    /// Creates a new transfer syntax descriptor.
    ///
    /// - Parameters:
    ///   - uid: The DICOM Transfer Syntax UID.
    ///   - name: Human-readable name.
    ///   - isCompressed: Whether the syntax uses compression.
    ///   - isLossless: Whether the compression is lossless.
    ///   - codec: The codec framework, or `nil` for uncompressed syntaxes.
    public init(
        uid: String,
        name: String,
        isCompressed: Bool,
        isLossless: Bool,
        codec: CodecFramework?
    ) {
        self.uid = uid
        self.name = name
        self.isCompressed = isCompressed
        self.isLossless = isLossless
        self.codec = codec
    }
}

// MARK: - CodecFramework

/// Identifies the image codec framework responsible for a given transfer syntax.
///
/// Each case maps to a Raster-Lab framework integrated by Milestone 4.
public enum CodecFramework: String, Sendable, Codable, Equatable, CaseIterable {

    /// JPEG 2000 codec via [J2KSwift](https://github.com/Raster-Lab/J2KSwift).
    case jpeg2000 = "J2KSwift"

    /// JPEG-LS codec via [JLSwift](https://github.com/Raster-Lab/JLSwift).
    case jpegLS = "JLSwift"

    /// JPEG XL codec via [JXLSwift](https://github.com/Raster-Lab/JXLSwift).
    case jpegXL = "JXLSwift"

    /// JP3D volumetric codec via the J2K3D module of
    /// [J2KSwift](https://github.com/Raster-Lab/J2KSwift).
    case jp3d = "J2K3D"

    /// RLE Lossless — native implementation; no external framework.
    case rle = "RLE"
}

// MARK: - TransferSyntaxRegistry

/// A registry of all DICOM transfer syntaxes supported by the server.
///
/// The registry provides lookup by UID, codec framework queries, and
/// collections of UIDs suitable for DICOM association negotiation.
///
/// Reference: DICOM PS3.5 Section 10 — Transfer Syntax
/// Reference: DICOM PS3.6 Annex A — Registry of DICOM Unique Identifiers
public enum TransferSyntaxRegistry {

    // MARK: - Transfer Syntax UIDs

    /// Implicit VR Little Endian (1.2.840.10008.1.2).
    public static let implicitVRLittleEndianUID = "1.2.840.10008.1.2"

    /// Explicit VR Little Endian (1.2.840.10008.1.2.1).
    public static let explicitVRLittleEndianUID = "1.2.840.10008.1.2.1"

    /// Explicit VR Big Endian — retired (1.2.840.10008.1.2.2).
    public static let explicitVRBigEndianUID = "1.2.840.10008.1.2.2"

    /// Deflated Explicit VR Little Endian (1.2.840.10008.1.2.1.99).
    public static let deflatedExplicitVRLittleEndianUID = "1.2.840.10008.1.2.1.99"

    /// RLE Lossless (1.2.840.10008.1.2.5).
    public static let rleLosslessUID = "1.2.840.10008.1.2.5"

    /// JPEG 2000 Image Compression — Lossless Only (1.2.840.10008.1.2.4.90).
    public static let jpeg2000LosslessUID = "1.2.840.10008.1.2.4.90"

    /// JPEG 2000 Image Compression (1.2.840.10008.1.2.4.91).
    public static let jpeg2000LossyUID = "1.2.840.10008.1.2.4.91"

    /// JPEG-LS Lossless Image Compression (1.2.840.10008.1.2.4.80).
    public static let jpegLSLosslessUID = "1.2.840.10008.1.2.4.80"

    /// JPEG-LS Lossy (Near-Lossless) Image Compression (1.2.840.10008.1.2.4.81).
    public static let jpegLSNearLosslessUID = "1.2.840.10008.1.2.4.81"

    /// High-Throughput JPEG 2000 Lossless (1.2.840.10008.1.2.4.201).
    public static let htj2kLosslessUID = "1.2.840.10008.1.2.4.201"

    /// High-Throughput JPEG 2000 Lossy (1.2.840.10008.1.2.4.202).
    public static let htj2kLossyUID = "1.2.840.10008.1.2.4.202"

    /// High-Throughput JPEG 2000 Lossless RPCL (1.2.840.10008.1.2.4.203).
    public static let htj2kLosslessRPCLUID = "1.2.840.10008.1.2.4.203"

    /// JPEG XL Lossless (1.2.840.10008.1.2.4.110).
    ///
    /// > Note: JPEG XL transfer syntax UIDs are defined for research and
    /// > interoperability purposes. Official DICOM registration may differ.
    public static let jpegXLLosslessUID = "1.2.840.10008.1.2.4.110"

    /// JPEG XL Lossy (1.2.840.10008.1.2.4.111).
    ///
    /// > Note: JPEG XL transfer syntax UIDs are defined for research and
    /// > interoperability purposes. Official DICOM registration may differ.
    public static let jpegXLLossyUID = "1.2.840.10008.1.2.4.111"

    // MARK: - Registry

    /// All known transfer syntaxes, keyed by UID.
    public static let allSyntaxes: [String: TransferSyntaxInfo] = {
        var map: [String: TransferSyntaxInfo] = [:]
        for ts in allSyntaxList {
            map[ts.uid] = ts
        }
        return map
    }()

    /// Ordered list of all known transfer syntaxes.
    public static let allSyntaxList: [TransferSyntaxInfo] = [
        // Uncompressed
        TransferSyntaxInfo(uid: implicitVRLittleEndianUID, name: "Implicit VR Little Endian", isCompressed: false, isLossless: true, codec: nil),
        TransferSyntaxInfo(uid: explicitVRLittleEndianUID, name: "Explicit VR Little Endian", isCompressed: false, isLossless: true, codec: nil),
        TransferSyntaxInfo(uid: explicitVRBigEndianUID, name: "Explicit VR Big Endian (Retired)", isCompressed: false, isLossless: true, codec: nil),
        TransferSyntaxInfo(uid: deflatedExplicitVRLittleEndianUID, name: "Deflated Explicit VR Little Endian", isCompressed: true, isLossless: true, codec: nil),

        // RLE
        TransferSyntaxInfo(uid: rleLosslessUID, name: "RLE Lossless", isCompressed: true, isLossless: true, codec: .rle),

        // JPEG 2000
        TransferSyntaxInfo(uid: jpeg2000LosslessUID, name: "JPEG 2000 Lossless", isCompressed: true, isLossless: true, codec: .jpeg2000),
        TransferSyntaxInfo(uid: jpeg2000LossyUID, name: "JPEG 2000", isCompressed: true, isLossless: false, codec: .jpeg2000),

        // JPEG-LS
        TransferSyntaxInfo(uid: jpegLSLosslessUID, name: "JPEG-LS Lossless", isCompressed: true, isLossless: true, codec: .jpegLS),
        TransferSyntaxInfo(uid: jpegLSNearLosslessUID, name: "JPEG-LS Near-Lossless", isCompressed: true, isLossless: false, codec: .jpegLS),

        // HTJ2K (High-Throughput JPEG 2000)
        TransferSyntaxInfo(uid: htj2kLosslessUID, name: "HTJ2K Lossless", isCompressed: true, isLossless: true, codec: .jpeg2000),
        TransferSyntaxInfo(uid: htj2kLossyUID, name: "HTJ2K Lossy", isCompressed: true, isLossless: false, codec: .jpeg2000),
        TransferSyntaxInfo(uid: htj2kLosslessRPCLUID, name: "HTJ2K Lossless RPCL", isCompressed: true, isLossless: true, codec: .jpeg2000),

        // JPEG XL
        TransferSyntaxInfo(uid: jpegXLLosslessUID, name: "JPEG XL Lossless", isCompressed: true, isLossless: true, codec: .jpegXL),
        TransferSyntaxInfo(uid: jpegXLLossyUID, name: "JPEG XL Lossy", isCompressed: true, isLossless: false, codec: .jpegXL),
    ]

    // MARK: - Lookup Methods

    /// Returns the transfer syntax info for the given UID, or `nil` if unknown.
    ///
    /// - Parameter uid: The DICOM Transfer Syntax UID.
    /// - Returns: The transfer syntax descriptor, or `nil`.
    public static func info(for uid: String) -> TransferSyntaxInfo? {
        allSyntaxes[uid]
    }

    /// Returns whether the given transfer syntax UID is compressed.
    ///
    /// - Parameter uid: The DICOM Transfer Syntax UID.
    /// - Returns: `true` if the syntax uses compression; `false` otherwise.
    ///   Returns `false` for unknown UIDs.
    public static func isCompressed(_ uid: String) -> Bool {
        allSyntaxes[uid]?.isCompressed ?? false
    }

    /// Returns whether the given transfer syntax UID is lossless.
    ///
    /// - Parameter uid: The DICOM Transfer Syntax UID.
    /// - Returns: `true` if the syntax is lossless; `false` otherwise.
    ///   Returns `true` for unknown UIDs (conservative assumption).
    public static func isLossless(_ uid: String) -> Bool {
        allSyntaxes[uid]?.isLossless ?? true
    }

    /// Returns the codec framework for the given transfer syntax UID.
    ///
    /// - Parameter uid: The DICOM Transfer Syntax UID.
    /// - Returns: The codec framework, or `nil` for uncompressed syntaxes
    ///   or unknown UIDs.
    public static func codec(for uid: String) -> CodecFramework? {
        allSyntaxes[uid]?.codec
    }

    // MARK: - UID Collections

    /// UIDs of all uncompressed transfer syntaxes.
    public static let uncompressedUIDs: Set<String> = Set(
        allSyntaxList.filter { !$0.isCompressed }.map(\.uid)
    )

    /// UIDs of all compressed transfer syntaxes.
    public static let compressedUIDs: Set<String> = Set(
        allSyntaxList.filter { $0.isCompressed }.map(\.uid)
    )

    /// UIDs of all lossless transfer syntaxes (both compressed and uncompressed).
    public static let losslessUIDs: Set<String> = Set(
        allSyntaxList.filter(\.isLossless).map(\.uid)
    )

    /// UIDs of all transfer syntaxes handled by a given codec framework.
    ///
    /// - Parameter codec: The codec framework to filter by.
    /// - Returns: The set of transfer syntax UIDs for that codec.
    public static func uids(for codec: CodecFramework) -> Set<String> {
        Set(allSyntaxList.filter { $0.codec == codec }.map(\.uid))
    }

    /// All transfer syntax UIDs supported by this server, suitable for
    /// DICOM association negotiation.
    public static let allSupportedUIDs: Set<String> = Set(allSyntaxList.map(\.uid))
}
