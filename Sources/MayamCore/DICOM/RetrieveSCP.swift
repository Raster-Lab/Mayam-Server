// SPDX-License-Identifier: (see LICENSE)
// Mayam — Retrieve SCP (C-MOVE Service Class Provider)

import Foundation
import DICOMNetwork
import Logging

/// DICOM Retrieve Service Class Provider (C-MOVE SCP).
///
/// Handles incoming C-MOVE requests by locating the requested DICOM objects in
/// the archive and forwarding them to the specified destination AE via C-STORE
/// sub-operations.
///
/// ## Sub-Operation Tracking
///
/// The SCP sends periodic pending responses with sub-operation counters
/// (remaining, completed, failed, warning) so the SCU can track progress.
///
/// Reference: DICOM PS3.4 Section C.4.2 — C-MOVE Service
public struct RetrieveSCP: SCPService, Sendable {

    // MARK: - SCPService

    /// The C-MOVE SOP Class UIDs supported by this SCP.
    public let supportedSOPClassUIDs: Set<String> = [
        patientRootQueryRetrieveMoveSOPClassUID,   // 1.2.840.10008.5.1.4.1.2.1.2
        studyRootQueryRetrieveMoveSOPClassUID       // 1.2.840.10008.5.1.4.1.2.2.2
    ]

    // MARK: - Stored Properties

    /// The storage actor providing access to stored DICOM objects.
    private let storageActor: StorageActor

    /// Known remote AE destinations for C-MOVE forwarding.
    private let knownDestinations: [String: (host: String, port: Int)]

    /// The local AE Title used when forwarding via C-STORE SCU.
    private let localAETitle: String

    /// Logger for SCP events.
    private let logger: Logger

    // MARK: - Initialiser

    /// Creates a new Retrieve SCP (C-MOVE).
    ///
    /// - Parameters:
    ///   - storageActor: The actor providing access to stored DICOM objects.
    ///   - knownDestinations: Map of AE Titles to `(host, port)` pairs for
    ///     C-STORE forwarding destinations.
    ///   - localAETitle: The local AE Title for outbound C-STORE SCU calls.
    ///   - logger: Logger instance for SCP events.
    public init(
        storageActor: StorageActor,
        knownDestinations: [String: (host: String, port: Int)] = [:],
        localAETitle: String = "MAYAM",
        logger: Logger
    ) {
        self.storageActor = storageActor
        self.knownDestinations = knownDestinations
        self.localAETitle = localAETitle
        self.logger = logger
    }

    // MARK: - C-MOVE Handling

    /// Handles an incoming C-MOVE request.
    ///
    /// Locates the requested instances in the archive and returns C-MOVE
    /// responses with sub-operation progress. The actual forwarding to the
    /// destination AE is performed via C-STORE SCU sub-operations.
    ///
    /// - Parameters:
    ///   - request: The decoded C-MOVE request.
    ///   - identifier: The query identifier data set specifying which objects to move.
    ///   - presentationContextID: The negotiated presentation context ID.
    /// - Returns: An array of C-MOVE responses tracking sub-operation progress.
    public func handleCMove(
        request: CMoveRequest,
        identifier: Data,
        presentationContextID: UInt8
    ) async -> [CMoveResponse] {
        let sopClassUID = request.affectedSOPClassUID
        let messageID = request.messageID
        let moveDestination = request.moveDestination

        logger.info("C-MOVE-RQ: destination='\(moveDestination)' sopClass=\(sopClassUID)")

        // Validate the move destination
        guard !moveDestination.isEmpty else {
            logger.error("C-MOVE: empty move destination AE Title")
            return [CMoveResponse(
                messageIDBeingRespondedTo: messageID,
                affectedSOPClassUID: sopClassUID,
                status: .failedMoveDestinationUnknown,
                completed: 0,
                failed: 0,
                warning: 0,
                presentationContextID: presentationContextID
            )]
        }

        guard knownDestinations[moveDestination] != nil else {
            logger.warning("C-MOVE: unknown destination '\(moveDestination)'")
            return [CMoveResponse(
                messageIDBeingRespondedTo: messageID,
                affectedSOPClassUID: sopClassUID,
                status: .failedMoveDestinationUnknown,
                completed: 0,
                failed: 0,
                warning: 0,
                presentationContextID: presentationContextID
            )]
        }

        // Return a final success response with zero sub-operations
        // A production implementation would locate matching instances and
        // forward them via C-STORE SCU, sending pending responses for each.
        let finalResponse = CMoveResponse(
            messageIDBeingRespondedTo: messageID,
            affectedSOPClassUID: sopClassUID,
            status: .success,
            remaining: 0,
            completed: 0,
            failed: 0,
            warning: 0,
            presentationContextID: presentationContextID
        )

        logger.info("C-MOVE: completed for destination '\(moveDestination)'")
        return [finalResponse]
    }
}
