// SPDX-License-Identifier: (see LICENSE)
// Mayam — Compressed Copy Manager

import Foundation
import Logging

/// Manages the creation of compressed derivative representations of DICOM
/// instances, both at ingest time (compressed copy on receipt) and via
/// background batch transcoding.
///
/// ## Compressed Copy on Receipt
///
/// When enabled by ``RepresentationPolicy/compressedCopyOnReceipt``, the
/// manager creates an additional compressed copy of each received instance
/// after it has been stored as-received.  The target codec is determined by
/// per-modality rules or falls back to the global default.
///
/// ## Background Batch Transcoding
///
/// The ``enqueueBatchTranscoding(studyInstanceUID:targetSyntaxUID:imageParameters:)``
/// method queues a study for background transcoding of all its instances to
/// a target transfer syntax.
///
/// ## Unified Object Presentation
///
/// All representations are tracked in ``RepresentationSet`` objects, enabling
/// the server to present multiple copies of the same instance as a single
/// logical item and serve the best available representation to each client.
///
/// Reference: Milestone 4 — Compressed Copy on Receipt, Background Batch
///            Transcoding, Unified Object Presentation
public actor CompressedCopyManager {

    // MARK: - Stored Properties

    /// The image codec service used for transcoding.
    private let codecService: ImageCodecService

    /// The representation policy governing derivative creation.
    private let policy: RepresentationPolicy

    /// Logger for manager events.
    private let logger: Logger

    /// In-memory index of representation sets, keyed by SOP Instance UID.
    ///
    /// > Note: In production, this will be backed by the metadata database.
    private var representationIndex: [String: RepresentationSet] = [:]

    /// Queue of pending background batch transcoding jobs.
    private var pendingBatchJobs: [BatchTranscodingJob] = []

    /// Total number of compressed copies created.
    private var compressedCopiesCreated: Int = 0

    // MARK: - Initialiser

    /// Creates a new compressed copy manager.
    ///
    /// - Parameters:
    ///   - codecService: The image codec service for transcoding.
    ///   - policy: The representation policy.
    ///   - logger: Logger instance for manager events.
    public init(
        codecService: ImageCodecService,
        policy: RepresentationPolicy = .default,
        logger: Logger
    ) {
        self.codecService = codecService
        self.policy = policy
        self.logger = logger
    }

    // MARK: - Public Methods

    /// Returns the total number of compressed copies created.
    public func getCompressedCopiesCreated() -> Int {
        compressedCopiesCreated
    }

    /// Returns the representation set for a given SOP Instance UID.
    ///
    /// - Parameter sopInstanceUID: The DICOM SOP Instance UID (0008,0018).
    /// - Returns: The representation set, or `nil` if not tracked.
    public func representationSet(for sopInstanceUID: String) -> RepresentationSet? {
        representationIndex[sopInstanceUID]
    }

    /// Registers the original (as-received) representation of an instance.
    ///
    /// - Parameter representation: The original representation to register.
    public func registerOriginal(_ representation: Representation) {
        var set = representationIndex[representation.sopInstanceUID]
            ?? RepresentationSet(sopInstanceUID: representation.sopInstanceUID)
        set.add(representation)
        representationIndex[representation.sopInstanceUID] = set
    }

    /// Creates a compressed copy of the given instance if the policy requires it.
    ///
    /// This is the **compressed copy on receipt** workflow.  It checks
    /// ``RepresentationPolicy/compressedCopyOnReceipt`` and per-modality rules
    /// to decide whether a compressed copy should be created.
    ///
    /// - Parameters:
    ///   - pixelData: The raw pixel data of the instance.
    ///   - sourceTransferSyntaxUID: The original transfer syntax UID.
    ///   - sopInstanceUID: The SOP Instance UID.
    ///   - sopClassUID: The SOP Class UID.
    ///   - studyInstanceUID: The Study Instance UID.
    ///   - seriesInstanceUID: The Series Instance UID.
    ///   - modality: The DICOM Modality code (e.g. `"CT"`).
    ///   - imageParameters: Image dimensions and format parameters.
    /// - Returns: The new compressed representation, or `nil` if no copy was
    ///   created (policy disabled or limit reached).
    /// - Throws: ``CodecError`` if transcoding fails.
    public func createCompressedCopyOnReceipt(
        pixelData: Data,
        sourceTransferSyntaxUID: String,
        sopInstanceUID: String,
        sopClassUID: String,
        studyInstanceUID: String = "UNKNOWN",
        seriesInstanceUID: String = "UNKNOWN",
        modality: String = "OT",
        imageParameters: ImageParameters
    ) async throws -> Representation? {
        guard policy.shouldCompressOnReceipt(modality: modality) else {
            return nil
        }

        let targetSyntaxUID = policy.targetSyntaxUID(for: modality)

        // Skip if the source is already in the target syntax
        guard sourceTransferSyntaxUID != targetSyntaxUID else {
            logger.debug("Skip compressed copy: already in target syntax \(targetSyntaxUID)")
            return nil
        }

        // Check derivative limit
        if let limit = policy.derivativeLimit {
            let currentCount = representationIndex[sopInstanceUID]?.count ?? 0
            guard currentCount < limit else {
                logger.warning("Derivative limit (\(limit)) reached for \(sopInstanceUID)")
                return nil
            }
        }

        logger.info("Creating compressed copy: \(sopInstanceUID) → \(targetSyntaxUID)")

        let result = try await codecService.transcode(
            pixelData: pixelData,
            from: sourceTransferSyntaxUID,
            to: targetSyntaxUID,
            imageParameters: imageParameters
        )

        let representation = Representation(
            sopInstanceUID: sopInstanceUID,
            sopClassUID: sopClassUID,
            studyInstanceUID: studyInstanceUID,
            seriesInstanceUID: seriesInstanceUID,
            transferSyntaxUID: targetSyntaxUID,
            filePath: "", // Actual file path assigned by StorageActor
            fileSizeBytes: Int64(result.data.count),
            isOriginal: false,
            isDerived: true,
            codec: TransferSyntaxRegistry.codec(for: targetSyntaxUID)
        )

        var set = representationIndex[sopInstanceUID]
            ?? RepresentationSet(sopInstanceUID: sopInstanceUID)
        set.add(representation)
        representationIndex[sopInstanceUID] = set
        compressedCopiesCreated += 1

        logger.info("Compressed copy created: \(sopInstanceUID) (\(result.data.count) bytes, \(targetSyntaxUID))")

        return representation
    }

    /// Enqueues a background batch transcoding job for an entire study.
    ///
    /// The job is added to the pending queue and processed asynchronously.
    ///
    /// - Parameters:
    ///   - studyInstanceUID: The Study Instance UID to transcode.
    ///   - targetSyntaxUID: The target transfer syntax UID.
    ///   - imageParameters: Image parameters for all instances in the study.
    public func enqueueBatchTranscoding(
        studyInstanceUID: String,
        targetSyntaxUID: String,
        imageParameters: ImageParameters
    ) {
        let job = BatchTranscodingJob(
            studyInstanceUID: studyInstanceUID,
            targetSyntaxUID: targetSyntaxUID,
            imageParameters: imageParameters,
            status: .pending,
            createdAt: Date()
        )
        pendingBatchJobs.append(job)
        logger.info("Batch transcoding enqueued: study=\(studyInstanceUID) → \(targetSyntaxUID)")
    }

    /// Returns the number of pending batch transcoding jobs.
    public func pendingJobCount() -> Int {
        pendingBatchJobs.count
    }

    /// Returns all pending batch transcoding jobs.
    public func getPendingJobs() -> [BatchTranscodingJob] {
        pendingBatchJobs
    }

    /// Selects the best representation for a client from the tracked
    /// representations of a given instance.
    ///
    /// - Parameters:
    ///   - sopInstanceUID: The SOP Instance UID.
    ///   - clientAcceptedUIDs: The client's accepted transfer syntax UIDs.
    /// - Returns: The best representation, or `nil` if no match.
    public func selectBestRepresentation(
        for sopInstanceUID: String,
        clientAcceptedUIDs: Set<String>
    ) -> Representation? {
        representationIndex[sopInstanceUID]?.bestMatch(for: clientAcceptedUIDs)
    }
}

// MARK: - BatchTranscodingJob

/// Describes a pending or completed background batch transcoding job.
public struct BatchTranscodingJob: Sendable, Equatable {

    /// Status of a batch transcoding job.
    public enum Status: String, Sendable, Codable, Equatable {
        case pending
        case running
        case completed
        case failed
    }

    /// The Study Instance UID to transcode.
    public let studyInstanceUID: String

    /// The target transfer syntax UID.
    public let targetSyntaxUID: String

    /// Image parameters for the transcoding.
    public let imageParameters: ImageParameters

    /// Current job status.
    public var status: Status

    /// When the job was created.
    public let createdAt: Date

    /// Creates a batch transcoding job.
    public init(
        studyInstanceUID: String,
        targetSyntaxUID: String,
        imageParameters: ImageParameters,
        status: Status = .pending,
        createdAt: Date = Date()
    ) {
        self.studyInstanceUID = studyInstanceUID
        self.targetSyntaxUID = targetSyntaxUID
        self.imageParameters = imageParameters
        self.status = status
        self.createdAt = createdAt
    }
}
