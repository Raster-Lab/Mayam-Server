// SPDX-License-Identifier: (see LICENSE)
// Mayam — Codec Error Types

import Foundation

/// Errors that may occur during image codec operations.
///
/// These errors cover transcoding, encoding, decoding, and configuration
/// validation for the integrated codec frameworks (J2KSwift, JLSwift,
/// JXLSwift, J2K3D).
public enum CodecError: Error, Sendable, CustomStringConvertible {

    /// The requested transfer syntax is not supported for transcoding.
    case unsupportedTransferSyntax(uid: String)

    /// Encoding failed for the given codec and reason.
    case encodingFailed(codec: CodecFramework, reason: String)

    /// Decoding failed for the given codec and reason.
    case decodingFailed(codec: CodecFramework, reason: String)

    /// The source data is not valid for the requested transcoding operation.
    case invalidSourceData(reason: String)

    /// The transcoding operation is not supported (e.g. lossy-to-lossless).
    case transcodingNotSupported(from: String, to: String)

    /// The maximum number of representations per study has been reached.
    case derivativeLimitExceeded(studyInstanceUID: String, limit: Int)

    /// A background transcoding job failed.
    case batchTranscodingFailed(studyInstanceUID: String, reason: String)

    // MARK: - CustomStringConvertible

    public var description: String {
        switch self {
        case .unsupportedTransferSyntax(let uid):
            return "Unsupported transfer syntax: '\(uid)'"
        case .encodingFailed(let codec, let reason):
            return "Encoding failed (\(codec.rawValue)): \(reason)"
        case .decodingFailed(let codec, let reason):
            return "Decoding failed (\(codec.rawValue)): \(reason)"
        case .invalidSourceData(let reason):
            return "Invalid source data: \(reason)"
        case .transcodingNotSupported(let from, let to):
            return "Transcoding not supported: '\(from)' → '\(to)'"
        case .derivativeLimitExceeded(let uid, let limit):
            return "Derivative limit (\(limit)) exceeded for study '\(uid)'"
        case .batchTranscodingFailed(let uid, let reason):
            return "Batch transcoding failed for study '\(uid)': \(reason)"
        }
    }
}
