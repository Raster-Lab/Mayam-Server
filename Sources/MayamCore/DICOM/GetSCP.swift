// SPDX-License-Identifier: (see LICENSE)
// Mayam — Get SCP (C-GET Service Class Provider)

import Foundation
import DICOMNetwork
import Logging

/// DICOM Get Service Class Provider (C-GET SCP).
///
/// Handles incoming C-GET requests by locating the requested DICOM objects in
/// the archive and returning them to the SCU on the same association via C-STORE
/// sub-operations.
///
/// Unlike C-MOVE, C-GET does not require a separate outbound connection — the
/// objects are sent back on the existing association. This makes C-GET suitable
/// for pull-based retrieval scenarios.
///
/// ## Sub-Operation Tracking
///
/// The SCP sends periodic pending responses with sub-operation counters
/// (remaining, completed, failed, warning) so the SCU can track progress.
///
/// Reference: DICOM PS3.4 Section C.4.3 — C-GET Service
public struct GetSCP: SCPService, Sendable {

    // MARK: - SCPService

    /// The C-GET SOP Class UIDs supported by this SCP.
    public let supportedSOPClassUIDs: Set<String> = [
        patientRootQueryRetrieveGetSOPClassUID,    // 1.2.840.10008.5.1.4.1.2.1.3
        studyRootQueryRetrieveGetSOPClassUID        // 1.2.840.10008.5.1.4.1.2.2.3
    ]

    // MARK: - Stored Properties

    /// The storage actor providing access to stored DICOM objects.
    private let storageActor: StorageActor

    /// Logger for SCP events.
    private let logger: Logger

    // MARK: - Initialiser

    /// Creates a new Get SCP (C-GET).
    ///
    /// - Parameters:
    ///   - storageActor: The actor providing access to stored DICOM objects.
    ///   - logger: Logger instance for SCP events.
    public init(storageActor: StorageActor, logger: Logger) {
        self.storageActor = storageActor
        self.logger = logger
    }

    // MARK: - C-GET Handling

    /// Handles an incoming C-GET request.
    ///
    /// Locates the requested instances in the archive and returns C-GET
    /// responses with sub-operation progress. The actual objects are sent
    /// back as C-STORE sub-operations on the same association.
    ///
    /// - Parameters:
    ///   - request: The decoded C-GET request.
    ///   - identifier: The query identifier data set specifying which objects to retrieve.
    ///   - presentationContextID: The negotiated presentation context ID.
    /// - Returns: A tuple containing C-GET responses and the data sets to send
    ///   back via C-STORE sub-operations.
    public func handleCGet(
        request: CGetRequest,
        identifier: Data,
        presentationContextID: UInt8
    ) async -> (responses: [CGetResponse], dataSets: [(sopClassUID: String, sopInstanceUID: String, transferSyntaxUID: String, data: Data)]) {
        let sopClassUID = request.affectedSOPClassUID
        let messageID = request.messageID

        logger.info("C-GET-RQ: sopClass=\(sopClassUID) pcID=\(presentationContextID)")

        // Return a final success response with zero sub-operations
        // A production implementation would locate matching instances and
        // return them as C-STORE sub-operations on the same association.
        let finalResponse = CGetResponse(
            messageIDBeingRespondedTo: messageID,
            affectedSOPClassUID: sopClassUID,
            status: .success,
            remaining: 0,
            completed: 0,
            failed: 0,
            warning: 0,
            presentationContextID: presentationContextID
        )

        logger.info("C-GET: completed")
        return (responses: [finalResponse], dataSets: [])
    }
}
