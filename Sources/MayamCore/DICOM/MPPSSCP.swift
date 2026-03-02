// SPDX-License-Identifier: (see LICENSE)
// Mayam — Modality Performed Procedure Step SCP

import Foundation
import DICOMNetwork

// MARK: - MPPSSCP

/// Handles Modality Performed Procedure Step (MPPS) N-CREATE and N-SET requests.
///
/// The MPPS SCP receives procedure status updates from modalities. When a
/// procedure begins, the modality sends an N-CREATE to create the MPPS
/// instance. When the procedure completes or is discontinued, the modality
/// sends an N-SET to update the status.
///
/// Reference: DICOM PS3.4 Annex F — Modality Performed Procedure Step SOP Class
public actor MPPSSCP {

    // MARK: - Constants

    /// Modality Performed Procedure Step SOP Class UID.
    /// Reference: DICOM PS3.4 Annex F.
    public static let sopClassUID = "1.2.840.10008.3.1.2.3.3"

    // MARK: - Stored Properties

    /// In-memory store of MPPS instances keyed by SOP Instance UID.
    private var instances: [String: PerformedProcedureStep] = [:]

    /// Logger for MPPS events.
    private let logger: MayamLogger

    /// Optional callback invoked when an MPPS status changes.
    private let statusChangeHandler: (@Sendable (PerformedProcedureStep) async -> Void)?

    // MARK: - Initialiser

    /// Creates a new MPPS SCP.
    ///
    /// - Parameters:
    ///   - logger: Logger instance for MPPS events.
    ///   - statusChangeHandler: Optional callback invoked on status changes.
    public init(
        logger: MayamLogger,
        statusChangeHandler: (@Sendable (PerformedProcedureStep) async -> Void)? = nil
    ) {
        self.logger = logger
        self.statusChangeHandler = statusChangeHandler
    }

    // MARK: - Public Methods

    /// Processes an N-CREATE request to create a new MPPS instance.
    ///
    /// - Parameters:
    ///   - sopInstanceUID: The SOP Instance UID for the new MPPS.
    ///   - dataSet: The N-CREATE attribute data set.
    /// - Returns: The created ``PerformedProcedureStep``.
    /// - Throws: ``MPPSError/duplicateInstance(sopInstanceUID:)`` if the
    ///   instance already exists.
    public func handleNCreate(
        sopInstanceUID: String,
        dataSet: Data
    ) async throws -> PerformedProcedureStep {
        guard instances[sopInstanceUID] == nil else {
            throw MPPSError.duplicateInstance(sopInstanceUID: sopInstanceUID)
        }

        logger.info("MPPS N-CREATE: Creating instance '\(sopInstanceUID)'")

        let attributes = parseMPPSAttributes(from: dataSet)

        let mpps = PerformedProcedureStep(
            sopInstanceUID: sopInstanceUID,
            status: .inProgress,
            studyInstanceUID: attributes.studyInstanceUID,
            accessionNumber: attributes.accessionNumber,
            patientID: attributes.patientID,
            patientName: attributes.patientName,
            modality: attributes.modality,
            performedStationAETitle: attributes.performedStationAETitle,
            performedStationName: attributes.performedStationName,
            performedStartDate: attributes.performedStartDate,
            performedStartTime: attributes.performedStartTime,
            performedProcedureStepDescription: attributes.performedProcedureStepDescription,
            performedProcedureStepID: attributes.performedProcedureStepID,
            scheduledProcedureStepID: attributes.scheduledProcedureStepID
        )

        instances[sopInstanceUID] = mpps

        if let handler = statusChangeHandler {
            await handler(mpps)
        }

        logger.info("MPPS N-CREATE: Instance '\(sopInstanceUID)' created successfully")
        return mpps
    }

    /// Processes an N-SET request to update an existing MPPS instance.
    ///
    /// - Parameters:
    ///   - sopInstanceUID: The SOP Instance UID of the MPPS to update.
    ///   - dataSet: The N-SET attribute data set.
    /// - Returns: The updated ``PerformedProcedureStep``.
    /// - Throws: ``MPPSError`` if the instance is not found, already
    ///   finalised, or the state transition is invalid.
    public func handleNSet(
        sopInstanceUID: String,
        dataSet: Data
    ) async throws -> PerformedProcedureStep {
        guard var mpps = instances[sopInstanceUID] else {
            throw MPPSError.instanceNotFound(sopInstanceUID: sopInstanceUID)
        }

        guard mpps.status == .inProgress else {
            throw MPPSError.instanceFinalised(sopInstanceUID: sopInstanceUID)
        }

        logger.info("MPPS N-SET: Updating instance '\(sopInstanceUID)'")

        let attributes = parseMPPSAttributes(from: dataSet)

        // Update status if provided
        if let newStatusRaw = attributes.status {
            guard let newStatus = PerformedProcedureStep.Status(rawValue: newStatusRaw) else {
                throw MPPSError.invalidStateTransition(from: mpps.status, to: .completed)
            }
            guard newStatus == .completed || newStatus == .discontinued else {
                throw MPPSError.invalidStateTransition(from: mpps.status, to: newStatus)
            }
            mpps.status = newStatus
        }

        // Update optional fields if provided
        if let endDate = attributes.performedEndDate {
            mpps.performedEndDate = endDate
        }
        if let endTime = attributes.performedEndTime {
            mpps.performedEndTime = endTime
        }
        if let desc = attributes.performedProcedureStepDescription {
            mpps.performedProcedureStepDescription = desc
        }

        mpps.updatedAt = Date()
        instances[sopInstanceUID] = mpps

        if let handler = statusChangeHandler {
            await handler(mpps)
        }

        logger.info("MPPS N-SET: Instance '\(sopInstanceUID)' updated to '\(mpps.status.rawValue)'")
        return mpps
    }

    /// Returns a specific MPPS instance by SOP Instance UID.
    ///
    /// - Parameter sopInstanceUID: The SOP Instance UID to look up.
    /// - Returns: The matching ``PerformedProcedureStep``.
    /// - Throws: ``MPPSError/instanceNotFound(sopInstanceUID:)`` if not found.
    public func getInstance(sopInstanceUID: String) throws -> PerformedProcedureStep {
        guard let mpps = instances[sopInstanceUID] else {
            throw MPPSError.instanceNotFound(sopInstanceUID: sopInstanceUID)
        }
        return mpps
    }

    /// Returns all MPPS instances.
    ///
    /// - Returns: An array of all ``PerformedProcedureStep`` records.
    public func getAllInstances() -> [PerformedProcedureStep] {
        Array(instances.values)
    }

    /// Returns the count of MPPS instances.
    public func instanceCount() -> Int {
        instances.count
    }

    // MARK: - Private Methods

    /// Parsed MPPS attribute values from a raw DICOM data set.
    private struct MPPSAttributes {
        var studyInstanceUID: String?
        var accessionNumber: String?
        var patientID: String?
        var patientName: String?
        var modality: String?
        var performedStationAETitle: String?
        var performedStationName: String?
        var performedStartDate: String?
        var performedStartTime: String?
        var performedEndDate: String?
        var performedEndTime: String?
        var performedProcedureStepDescription: String?
        var performedProcedureStepID: String?
        var scheduledProcedureStepID: String?
        var status: String?
    }

    /// Parses MPPS-relevant attributes from a raw DICOM data set.
    ///
    /// - Parameter data: The raw DICOM data set bytes.
    /// - Returns: Parsed MPPS attribute values.
    private func parseMPPSAttributes(from data: Data) -> MPPSAttributes {
        var attrs = MPPSAttributes()
        var offset = 0

        while offset + 8 <= data.count {
            let group = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            let element = UInt16(data[offset + 2]) | (UInt16(data[offset + 3]) << 8)

            // Determine VR encoding
            let byte4 = data[offset + 4]
            let byte5 = data[offset + 5]
            let isExplicitVR = (byte4 >= 0x41 && byte4 <= 0x5A) && (byte5 >= 0x41 && byte5 <= 0x5A)

            var valueLength: UInt32 = 0
            var valueOffset = offset + 8

            if isExplicitVR {
                let vr0 = Character(UnicodeScalar(byte4))
                let vr1 = Character(UnicodeScalar(byte5))
                let vrStr = String([vr0, vr1])

                if ["OB", "OD", "OF", "OL", "OW", "SQ", "UC", "UN", "UR", "UT"].contains(vrStr) {
                    if offset + 12 <= data.count {
                        valueLength = UInt32(data[offset + 8]) | (UInt32(data[offset + 9]) << 8) |
                                      (UInt32(data[offset + 10]) << 16) | (UInt32(data[offset + 11]) << 24)
                        valueOffset = offset + 12
                    }
                } else {
                    valueLength = UInt32(UInt16(data[offset + 6]) | (UInt16(data[offset + 7]) << 8))
                    valueOffset = offset + 8
                }
            } else {
                valueLength = UInt32(data[offset + 4]) | (UInt32(data[offset + 5]) << 8) |
                              (UInt32(data[offset + 6]) << 16) | (UInt32(data[offset + 7]) << 24)
                valueOffset = offset + 8
            }

            if valueLength == 0xFFFFFFFF { valueLength = 0 }

            let endOffset = valueOffset + Int(valueLength)
            if endOffset <= data.count && valueLength > 0 {
                let valueData = data[valueOffset..<endOffset]
                let stringValue = String(data: Data(valueData), encoding: .ascii)?
                    .trimmingCharacters(in: .whitespaces.union(.controlCharacters))

                switch (group, element) {
                case (0x0008, 0x0050): attrs.accessionNumber = stringValue
                case (0x0008, 0x0060): attrs.modality = stringValue
                case (0x0010, 0x0010): attrs.patientName = stringValue
                case (0x0010, 0x0020): attrs.patientID = stringValue
                case (0x0020, 0x000D): attrs.studyInstanceUID = stringValue
                case (0x0040, 0x0241): attrs.performedStationAETitle = stringValue
                case (0x0040, 0x0242): attrs.performedStationName = stringValue
                case (0x0040, 0x0244): attrs.performedStartDate = stringValue
                case (0x0040, 0x0245): attrs.performedStartTime = stringValue
                case (0x0040, 0x0250): attrs.performedEndDate = stringValue
                case (0x0040, 0x0251): attrs.performedEndTime = stringValue
                case (0x0040, 0x0252): attrs.status = stringValue
                case (0x0040, 0x0253): attrs.performedProcedureStepID = stringValue
                case (0x0040, 0x0254): attrs.performedProcedureStepDescription = stringValue
                case (0x0040, 0x0009): attrs.scheduledProcedureStepID = stringValue
                default: break
                }
            }

            offset = endOffset > offset ? endOffset : offset + 8
        }

        return attrs
    }
}
