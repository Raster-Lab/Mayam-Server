// SPDX-License-Identifier: (see LICENSE)
// Mayam — Query/Retrieve Error Types

import Foundation

/// Errors that may occur during DICOM Query/Retrieve operations.
///
/// Reference: DICOM PS3.4 Annex C — Query/Retrieve Service Class
public enum QueryRetrieveError: Error, Sendable, CustomStringConvertible {

    /// The requested query level is not supported by the information model.
    case unsupportedQueryLevel(String)

    /// The query identifier data set could not be parsed.
    case invalidIdentifier(reason: String)

    /// The move destination AE Title is unknown or not configured.
    case unknownMoveDestination(aeTitle: String)

    /// A sub-operation failed during C-MOVE or C-GET.
    case subOperationFailed(completed: UInt16, failed: UInt16, warning: UInt16)

    /// No matching records found for the query.
    case noMatchesFound

    /// The query was cancelled by the SCU.
    case queryCancelled

    /// A database query error occurred.
    case databaseError(underlying: any Error)

    /// The file for the requested instance could not be found.
    case instanceFileNotFound(sopInstanceUID: String, path: String)

    // MARK: - CustomStringConvertible

    public var description: String {
        switch self {
        case .unsupportedQueryLevel(let level):
            return "Unsupported query level: '\(level)'"
        case .invalidIdentifier(let reason):
            return "Invalid query identifier: \(reason)"
        case .unknownMoveDestination(let aeTitle):
            return "Unknown move destination AE Title: '\(aeTitle)'"
        case .subOperationFailed(let completed, let failed, let warning):
            return "Sub-operation failed: completed=\(completed) failed=\(failed) warning=\(warning)"
        case .noMatchesFound:
            return "No matching records found"
        case .queryCancelled:
            return "Query cancelled by SCU"
        case .databaseError(let underlying):
            return "Database error during query: \(underlying)"
        case .instanceFileNotFound(let uid, let path):
            return "Instance file not found: SOP Instance UID='\(uid)' path='\(path)'"
        }
    }
}
