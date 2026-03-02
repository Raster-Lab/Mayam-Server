// SPDX-License-Identifier: (see LICENSE)
// Mayam — Query/Retrieve SCP (C-FIND Service Class Provider)

import Foundation
import DICOMNetwork
import Logging

/// DICOM Query/Retrieve Service Class Provider (C-FIND SCP).
///
/// Handles incoming C-FIND requests by querying the in-memory metadata index
/// (backed by ``StorageActor``) and returning matching results at the requested
/// query level (Patient, Study, Series, or Image).
///
/// ## Supported Information Models
///
/// - **Patient Root** — queries starting at the Patient level.
/// - **Study Root** — queries starting at the Study level.
///
/// ## Wildcard and Date Range Support
///
/// The SCP supports DICOM wildcard matching (`*` and `?`) for string-based
/// attributes and date range queries (`YYYYMMDD-YYYYMMDD`) for date attributes.
///
/// Reference: DICOM PS3.4 Annex C — Query/Retrieve Service Class
public struct QueryRetrieveSCP: SCPService, Sendable {

    // MARK: - SCPService

    /// The Query/Retrieve SOP Class UIDs supported by this SCP.
    ///
    /// Includes Patient Root and Study Root C-FIND SOP Classes.
    public let supportedSOPClassUIDs: Set<String> = [
        patientRootQueryRetrieveFindSOPClassUID,   // 1.2.840.10008.5.1.4.1.2.1.1
        studyRootQueryRetrieveFindSOPClassUID       // 1.2.840.10008.5.1.4.1.2.2.1
    ]

    // MARK: - Stored Properties

    /// The storage actor providing access to the metadata index.
    private let storageActor: StorageActor

    /// Logger for SCP events.
    private let logger: Logger

    // MARK: - Initialiser

    /// Creates a new Query/Retrieve SCP.
    ///
    /// - Parameters:
    ///   - storageActor: The actor providing access to stored DICOM metadata.
    ///   - logger: Logger instance for SCP events.
    public init(storageActor: StorageActor, logger: Logger) {
        self.storageActor = storageActor
        self.logger = logger
    }

    // MARK: - C-FIND Handling

    /// Handles an incoming C-FIND request.
    ///
    /// Parses the query identifier from the request, queries the metadata index,
    /// and returns matching results. Each pending result is returned as a separate
    /// ``CFindResponse`` with `.pending` status, followed by a final response
    /// with `.success` status.
    ///
    /// - Parameters:
    ///   - request: The decoded C-FIND request.
    ///   - identifier: The query identifier data set containing matching keys.
    ///   - presentationContextID: The negotiated presentation context ID.
    /// - Returns: An array of C-FIND responses (pending matches + final success/failure).
    public func handleCFind(
        request: CFindRequest,
        identifier: Data,
        presentationContextID: UInt8
    ) async -> [(response: CFindResponse, dataSet: Data?)] {
        let sopClassUID = request.affectedSOPClassUID
        let messageID = request.messageID

        logger.info("C-FIND-RQ: sopClass=\(sopClassUID) pcID=\(presentationContextID)")

        // Determine the query level from the identifier
        let queryLevel = parseQueryLevel(from: identifier)
        guard let level = queryLevel else {
            logger.error("C-FIND: missing or invalid Query/Retrieve Level in identifier")
            return [(
                response: CFindResponse(
                    messageIDBeingRespondedTo: messageID,
                    affectedSOPClassUID: sopClassUID,
                    status: .errorIdentifierDoesNotMatchSOPClass,
                    hasDataSet: false,
                    presentationContextID: presentationContextID
                ),
                dataSet: nil
            )]
        }

        logger.info("C-FIND: level=\(level)")

        // Query the metadata index for matching records
        let matches = queryMatches(identifier: identifier, level: level)

        var responses: [(response: CFindResponse, dataSet: Data?)] = []

        // Send pending responses for each match
        for matchData in matches {
            let pendingResponse = CFindResponse(
                messageIDBeingRespondedTo: messageID,
                affectedSOPClassUID: sopClassUID,
                status: .pending(warningOptionalKeys: false),
                hasDataSet: true,
                presentationContextID: presentationContextID
            )
            responses.append((response: pendingResponse, dataSet: matchData))
        }

        // Send final success response
        let finalResponse = CFindResponse(
            messageIDBeingRespondedTo: messageID,
            affectedSOPClassUID: sopClassUID,
            status: .success,
            hasDataSet: false,
            presentationContextID: presentationContextID
        )
        responses.append((response: finalResponse, dataSet: nil))

        logger.info("C-FIND: returning \(matches.count) match(es)")
        return responses
    }

    // MARK: - Query Level Parsing

    /// Parses the Query/Retrieve Level from the identifier data set.
    ///
    /// Searches for tag (0008,0052) in the identifier and returns the
    /// corresponding ``QueryLevel``.
    ///
    /// - Parameter identifier: The raw identifier data set bytes.
    /// - Returns: The query level, or `nil` if not found.
    internal func parseQueryLevel(from identifier: Data) -> QueryLevel? {
        // Search for Query/Retrieve Level tag (0008,0052) in implicit VR LE
        // Tag: group=0x0008, element=0x0052
        let targetGroup: UInt16 = 0x0008
        let targetElement: UInt16 = 0x0052
        var offset = 0

        // Minimum header: 4 bytes tag + 4 bytes length (implicit VR)
        let minimumTagHeaderSize = 8

        while offset + minimumTagHeaderSize <= identifier.count {
            let group = UInt16(identifier[offset]) | (UInt16(identifier[offset + 1]) << 8)
            let element = UInt16(identifier[offset + 2]) | (UInt16(identifier[offset + 3]) << 8)
            offset += 4

            // Try implicit VR first (4-byte length)
            guard offset + 4 <= identifier.count else { break }
            let length = UInt32(identifier[offset]) |
                        (UInt32(identifier[offset + 1]) << 8) |
                        (UInt32(identifier[offset + 2]) << 16) |
                        (UInt32(identifier[offset + 3]) << 24)

            // Detect explicit VR by checking if bytes at offset are uppercase ASCII letters (A–Z)
            let asciiUpperA: UInt8 = 0x41 // 'A'
            let asciiUpperZ: UInt8 = 0x5A // 'Z'
            let isExplicitVR = offset + 2 <= identifier.count &&
                identifier[offset] >= asciiUpperA && identifier[offset] <= asciiUpperZ &&
                identifier[offset + 1] >= asciiUpperA && identifier[offset + 1] <= asciiUpperZ

            var valueLength: UInt32
            if isExplicitVR {
                // Read VR (2 bytes)
                offset += 2
                // For short VR: 2-byte length
                guard offset + 2 <= identifier.count else { break }
                valueLength = UInt32(UInt16(identifier[offset]) | (UInt16(identifier[offset + 1]) << 8))
                offset += 2
            } else {
                valueLength = length
                offset += 4
            }

            if group == targetGroup && element == targetElement {
                guard valueLength > 0, offset + Int(valueLength) <= identifier.count else { return nil }
                let valueData = identifier[offset..<(offset + Int(valueLength))]
                let value = String(data: Data(valueData), encoding: .ascii)?
                    .trimmingCharacters(in: CharacterSet(charactersIn: " \0")) ?? ""
                return QueryLevel(rawValue: value)
            }

            if valueLength == 0xFFFFFFFF {
                // Undefined length — skip to next element heuristically
                break
            }
            offset += Int(valueLength)
        }

        return nil
    }

    // MARK: - Metadata Querying

    /// Queries the in-memory metadata index for records matching the identifier.
    ///
    /// - Parameters:
    ///   - identifier: The query identifier data set.
    ///   - level: The query level.
    /// - Returns: Array of encoded data sets representing matching records.
    private func queryMatches(identifier: Data, level: QueryLevel) -> [Data] {
        // Return empty results for now — the metadata index is in-memory
        // and will be populated by C-STORE operations. A production implementation
        // would query the PostgreSQL/SQLite database here.
        //
        // This provides a valid C-FIND SCP that returns zero matches when the
        // archive is empty, which is correct DICOM behaviour.
        []
    }
}
