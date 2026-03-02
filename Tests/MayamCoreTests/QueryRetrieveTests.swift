// SPDX-License-Identifier: (see LICENSE)
// Mayam — Query/Retrieve Service Tests

import XCTest
import NIOCore
import NIOEmbedded
import NIOPosix
@testable import MayamCore
import DICOMNetwork
import Logging

// MARK: - QueryRetrieveSCP Tests

final class QueryRetrieveSCPTests: XCTestCase {

    private func makeStorageActor() -> StorageActor {
        let logger = MayamLogger(label: "test.qr")
        return StorageActor(archivePath: NSTemporaryDirectory(), checksumEnabled: false, logger: logger)
    }

    func test_queryRetrieveSCP_supportedSOPClasses_containsFindUIDs() {
        let scp = QueryRetrieveSCP(storageActor: makeStorageActor(), logger: Logger(label: "test"))
        XCTAssertTrue(scp.supportedSOPClassUIDs.contains(patientRootQueryRetrieveFindSOPClassUID))
        XCTAssertTrue(scp.supportedSOPClassUIDs.contains(studyRootQueryRetrieveFindSOPClassUID))
        XCTAssertEqual(scp.supportedSOPClassUIDs.count, 2)
    }

    func test_queryRetrieveSCP_handleCFind_emptyArchive_returnsSuccessWithNoMatches() async {
        let scp = QueryRetrieveSCP(storageActor: makeStorageActor(), logger: Logger(label: "test"))

        // Build a minimal identifier with Query/Retrieve Level = STUDY
        let identifier = buildStudyLevelIdentifier()

        let request = CFindRequest(
            messageID: 1,
            affectedSOPClassUID: studyRootQueryRetrieveFindSOPClassUID,
            presentationContextID: 1
        )

        let responses = await scp.handleCFind(
            request: request,
            identifier: identifier,
            presentationContextID: 1
        )

        // Should have exactly one final response (success, no pending matches)
        XCTAssertEqual(responses.count, 1)
        XCTAssertTrue(responses[0].response.status.isSuccess)
        XCTAssertNil(responses[0].dataSet)
    }

    func test_queryRetrieveSCP_handleCFind_missingQueryLevel_returnsError() async {
        let scp = QueryRetrieveSCP(storageActor: makeStorageActor(), logger: Logger(label: "test"))

        // Empty identifier — no Query/Retrieve Level tag
        let request = CFindRequest(
            messageID: 42,
            affectedSOPClassUID: studyRootQueryRetrieveFindSOPClassUID,
            presentationContextID: 3
        )

        let responses = await scp.handleCFind(
            request: request,
            identifier: Data(),
            presentationContextID: 3
        )

        XCTAssertEqual(responses.count, 1)
        XCTAssertTrue(responses[0].response.status.isFailure)
        XCTAssertEqual(responses[0].response.presentationContextID, 3)
        XCTAssertEqual(responses[0].response.messageIDBeingRespondedTo, 42)
    }

    func test_queryRetrieveSCP_parseQueryLevel_patient() {
        let scp = QueryRetrieveSCP(storageActor: makeStorageActor(), logger: Logger(label: "test"))
        let identifier = buildQueryLevelIdentifier(level: "PATIENT")
        let level = scp.parseQueryLevel(from: identifier)
        XCTAssertEqual(level, .patient)
    }

    func test_queryRetrieveSCP_parseQueryLevel_study() {
        let scp = QueryRetrieveSCP(storageActor: makeStorageActor(), logger: Logger(label: "test"))
        let identifier = buildQueryLevelIdentifier(level: "STUDY")
        let level = scp.parseQueryLevel(from: identifier)
        XCTAssertEqual(level, .study)
    }

    func test_queryRetrieveSCP_parseQueryLevel_series() {
        let scp = QueryRetrieveSCP(storageActor: makeStorageActor(), logger: Logger(label: "test"))
        let identifier = buildQueryLevelIdentifier(level: "SERIES")
        let level = scp.parseQueryLevel(from: identifier)
        XCTAssertEqual(level, .series)
    }

    func test_queryRetrieveSCP_parseQueryLevel_image() {
        let scp = QueryRetrieveSCP(storageActor: makeStorageActor(), logger: Logger(label: "test"))
        let identifier = buildQueryLevelIdentifier(level: "IMAGE")
        let level = scp.parseQueryLevel(from: identifier)
        XCTAssertEqual(level, .image)
    }

    func test_queryRetrieveSCP_parseQueryLevel_empty_returnsNil() {
        let scp = QueryRetrieveSCP(storageActor: makeStorageActor(), logger: Logger(label: "test"))
        let level = scp.parseQueryLevel(from: Data())
        XCTAssertNil(level)
    }

    func test_queryRetrieveSCP_handleCFind_preservesMessageID() async {
        let scp = QueryRetrieveSCP(storageActor: makeStorageActor(), logger: Logger(label: "test"))
        let identifier = buildStudyLevelIdentifier()

        for messageID: UInt16 in [1, 100, 1000, UInt16.max] {
            let request = CFindRequest(
                messageID: messageID,
                affectedSOPClassUID: studyRootQueryRetrieveFindSOPClassUID,
                presentationContextID: 1
            )

            let responses = await scp.handleCFind(
                request: request,
                identifier: identifier,
                presentationContextID: 1
            )

            XCTAssertEqual(responses.last?.response.messageIDBeingRespondedTo, messageID)
        }
    }

    func test_queryRetrieveSCP_handleCFind_preservesPresentationContextID() async {
        let scp = QueryRetrieveSCP(storageActor: makeStorageActor(), logger: Logger(label: "test"))
        let identifier = buildStudyLevelIdentifier()

        for contextID: UInt8 in [1, 3, 5, 127] {
            let request = CFindRequest(
                messageID: 1,
                affectedSOPClassUID: studyRootQueryRetrieveFindSOPClassUID,
                presentationContextID: contextID
            )

            let responses = await scp.handleCFind(
                request: request,
                identifier: identifier,
                presentationContextID: contextID
            )

            XCTAssertEqual(responses.last?.response.presentationContextID, contextID)
        }
    }

    // MARK: - Helper — Build Identifier Data

    /// Builds a minimal Implicit VR LE identifier with Query/Retrieve Level = STUDY.
    private func buildStudyLevelIdentifier() -> Data {
        buildQueryLevelIdentifier(level: "STUDY")
    }

    /// Builds a minimal Implicit VR LE identifier with a given Query/Retrieve Level value.
    private func buildQueryLevelIdentifier(level: String) -> Data {
        var data = Data()
        // Tag (0008,0052) — Query/Retrieve Level
        data.append(contentsOf: [0x08, 0x00, 0x52, 0x00])
        // Length (4 bytes, Implicit VR)
        var valueData = level.data(using: .ascii) ?? Data()
        if valueData.count % 2 != 0 { valueData.append(0x20) }
        var length = UInt32(valueData.count).littleEndian
        data.append(Data(bytes: &length, count: 4))
        // Value
        data.append(valueData)
        return data
    }
}

// MARK: - RetrieveSCP Tests

final class RetrieveSCPTests: XCTestCase {

    private func makeStorageActor() -> StorageActor {
        let logger = MayamLogger(label: "test.retrieve")
        return StorageActor(archivePath: NSTemporaryDirectory(), checksumEnabled: false, logger: logger)
    }

    func test_retrieveSCP_supportedSOPClasses_containsMoveUIDs() {
        let scp = RetrieveSCP(storageActor: makeStorageActor(), logger: Logger(label: "test"))
        XCTAssertTrue(scp.supportedSOPClassUIDs.contains(patientRootQueryRetrieveMoveSOPClassUID))
        XCTAssertTrue(scp.supportedSOPClassUIDs.contains(studyRootQueryRetrieveMoveSOPClassUID))
        XCTAssertEqual(scp.supportedSOPClassUIDs.count, 2)
    }

    func test_retrieveSCP_handleCMove_unknownDestination_returnsMoveDestinationUnknown() async {
        let scp = RetrieveSCP(
            storageActor: makeStorageActor(),
            knownDestinations: ["KNOWN_AE": (host: "10.0.0.1", port: 11112)],
            logger: Logger(label: "test")
        )

        let request = CMoveRequest(
            messageID: 1,
            affectedSOPClassUID: studyRootQueryRetrieveMoveSOPClassUID,
            moveDestination: "UNKNOWN_AE",
            presentationContextID: 1
        )

        let responses = await scp.handleCMove(
            request: request,
            identifier: Data(),
            presentationContextID: 1
        )

        XCTAssertEqual(responses.count, 1)
        XCTAssertEqual(responses[0].status, .failedMoveDestinationUnknown)
    }

    func test_retrieveSCP_handleCMove_emptyDestination_returnsMoveDestinationUnknown() async {
        let scp = RetrieveSCP(
            storageActor: makeStorageActor(),
            logger: Logger(label: "test")
        )

        let request = CMoveRequest(
            messageID: 1,
            affectedSOPClassUID: studyRootQueryRetrieveMoveSOPClassUID,
            moveDestination: "",
            presentationContextID: 1
        )

        let responses = await scp.handleCMove(
            request: request,
            identifier: Data(),
            presentationContextID: 1
        )

        XCTAssertEqual(responses.count, 1)
        XCTAssertEqual(responses[0].status, .failedMoveDestinationUnknown)
    }

    func test_retrieveSCP_handleCMove_knownDestination_returnsSuccess() async {
        let scp = RetrieveSCP(
            storageActor: makeStorageActor(),
            knownDestinations: ["DEST_AE": (host: "10.0.0.1", port: 11112)],
            logger: Logger(label: "test")
        )

        let request = CMoveRequest(
            messageID: 1,
            affectedSOPClassUID: studyRootQueryRetrieveMoveSOPClassUID,
            moveDestination: "DEST_AE",
            presentationContextID: 1
        )

        let responses = await scp.handleCMove(
            request: request,
            identifier: Data(),
            presentationContextID: 1
        )

        XCTAssertEqual(responses.count, 1)
        XCTAssertTrue(responses[0].status.isSuccess)
    }

    func test_retrieveSCP_handleCMove_preservesMessageID() async {
        let scp = RetrieveSCP(
            storageActor: makeStorageActor(),
            knownDestinations: ["AE": (host: "h", port: 1)],
            logger: Logger(label: "test")
        )

        let request = CMoveRequest(
            messageID: 99,
            affectedSOPClassUID: studyRootQueryRetrieveMoveSOPClassUID,
            moveDestination: "AE",
            presentationContextID: 5
        )

        let responses = await scp.handleCMove(request: request, identifier: Data(), presentationContextID: 5)
        XCTAssertEqual(responses[0].messageIDBeingRespondedTo, 99)
    }
}

// MARK: - GetSCP Tests

final class GetSCPTests: XCTestCase {

    private func makeStorageActor() -> StorageActor {
        let logger = MayamLogger(label: "test.get")
        return StorageActor(archivePath: NSTemporaryDirectory(), checksumEnabled: false, logger: logger)
    }

    func test_getSCP_supportedSOPClasses_containsGetUIDs() {
        let scp = GetSCP(storageActor: makeStorageActor(), logger: Logger(label: "test"))
        XCTAssertTrue(scp.supportedSOPClassUIDs.contains(patientRootQueryRetrieveGetSOPClassUID))
        XCTAssertTrue(scp.supportedSOPClassUIDs.contains(studyRootQueryRetrieveGetSOPClassUID))
        XCTAssertEqual(scp.supportedSOPClassUIDs.count, 2)
    }

    func test_getSCP_handleCGet_emptyArchive_returnsSuccess() async {
        let scp = GetSCP(storageActor: makeStorageActor(), logger: Logger(label: "test"))

        let request = CGetRequest(
            messageID: 1,
            affectedSOPClassUID: studyRootQueryRetrieveGetSOPClassUID,
            presentationContextID: 1
        )

        let result = await scp.handleCGet(
            request: request,
            identifier: Data(),
            presentationContextID: 1
        )

        XCTAssertEqual(result.responses.count, 1)
        XCTAssertTrue(result.responses[0].status.isSuccess)
        XCTAssertTrue(result.dataSets.isEmpty)
    }

    func test_getSCP_handleCGet_preservesMessageID() async {
        let scp = GetSCP(storageActor: makeStorageActor(), logger: Logger(label: "test"))

        let request = CGetRequest(
            messageID: 77,
            affectedSOPClassUID: studyRootQueryRetrieveGetSOPClassUID,
            presentationContextID: 3
        )

        let result = await scp.handleCGet(request: request, identifier: Data(), presentationContextID: 3)
        XCTAssertEqual(result.responses[0].messageIDBeingRespondedTo, 77)
    }
}

// MARK: - SCPDispatcher Query/Retrieve Tests

final class SCPDispatcherQueryRetrieveTests: XCTestCase {

    private func makeStorageActor() -> StorageActor {
        let logger = MayamLogger(label: "test.dispatch")
        return StorageActor(archivePath: NSTemporaryDirectory(), checksumEnabled: false, logger: logger)
    }

    func test_scpDispatcher_handleCFind_withoutSCP_returnsFailure() async {
        let dispatcher = SCPDispatcher()

        let request = CFindRequest(
            messageID: 1,
            affectedSOPClassUID: studyRootQueryRetrieveFindSOPClassUID,
            presentationContextID: 1
        )

        let responses = await dispatcher.handleCFind(
            request: request,
            identifier: Data(),
            presentationContextID: 1
        )

        XCTAssertEqual(responses.count, 1)
        XCTAssertTrue(responses[0].response.status.isFailure)
    }

    func test_scpDispatcher_handleCFind_withSCP_delegatesToSCP() async {
        let storageActor = makeStorageActor()
        let qrSCP = QueryRetrieveSCP(storageActor: storageActor, logger: Logger(label: "test"))
        let dispatcher = SCPDispatcher(queryRetrieveSCP: qrSCP)

        let identifier = buildStudyLevelIdentifier()
        let request = CFindRequest(
            messageID: 1,
            affectedSOPClassUID: studyRootQueryRetrieveFindSOPClassUID,
            presentationContextID: 1
        )

        let responses = await dispatcher.handleCFind(
            request: request,
            identifier: identifier,
            presentationContextID: 1
        )

        // Empty archive: should return only the final success response
        XCTAssertEqual(responses.count, 1)
        XCTAssertTrue(responses[0].response.status.isSuccess)
    }

    func test_scpDispatcher_handleCMove_withoutSCP_returnsFailure() async {
        let dispatcher = SCPDispatcher()

        let request = CMoveRequest(
            messageID: 1,
            affectedSOPClassUID: studyRootQueryRetrieveMoveSOPClassUID,
            moveDestination: "DEST",
            presentationContextID: 1
        )

        let responses = await dispatcher.handleCMove(
            request: request,
            identifier: Data(),
            presentationContextID: 1
        )

        XCTAssertEqual(responses.count, 1)
        XCTAssertTrue(responses[0].status.isFailure)
    }

    func test_scpDispatcher_handleCGet_withoutSCP_returnsFailure() async {
        let dispatcher = SCPDispatcher()

        let request = CGetRequest(
            messageID: 1,
            affectedSOPClassUID: studyRootQueryRetrieveGetSOPClassUID,
            presentationContextID: 1
        )

        let result = await dispatcher.handleCGet(
            request: request,
            identifier: Data(),
            presentationContextID: 1
        )

        XCTAssertEqual(result.responses.count, 1)
        XCTAssertTrue(result.responses[0].status.isFailure)
    }

    func test_scpDispatcher_canBeCreatedWithAllSCPs() {
        let storageActor = makeStorageActor()
        let logger = Logger(label: "test")
        let qrSCP = QueryRetrieveSCP(storageActor: storageActor, logger: logger)
        let retrieveSCP = RetrieveSCP(storageActor: storageActor, logger: logger)
        let getSCP = GetSCP(storageActor: storageActor, logger: logger)

        let dispatcher = SCPDispatcher(
            queryRetrieveSCP: qrSCP,
            retrieveSCP: retrieveSCP,
            getSCP: getSCP
        )

        // Verify C-ECHO still works with the new SCPs registered
        let echoRequest = CEchoRequest(
            messageID: 1,
            affectedSOPClassUID: verificationSOPClassUID,
            presentationContextID: 1
        )
        let echoResponse = dispatcher.handleCEcho(request: echoRequest, presentationContextID: 1)
        XCTAssertTrue(echoResponse.status.isSuccess)
    }

    private func buildStudyLevelIdentifier() -> Data {
        var data = Data()
        data.append(contentsOf: [0x08, 0x00, 0x52, 0x00])
        let value = "STUDY ".data(using: .ascii)!
        var length = UInt32(value.count).littleEndian
        data.append(Data(bytes: &length, count: 4))
        data.append(value)
        return data
    }
}

// MARK: - QueryRetrieveError Tests

final class QueryRetrieveErrorTests: XCTestCase {

    func test_unsupportedQueryLevel_description() {
        let error = QueryRetrieveError.unsupportedQueryLevel("BOGUS")
        XCTAssertTrue(error.description.contains("BOGUS"))
    }

    func test_invalidIdentifier_description() {
        let error = QueryRetrieveError.invalidIdentifier(reason: "missing tag")
        XCTAssertTrue(error.description.contains("missing tag"))
    }

    func test_unknownMoveDestination_description() {
        let error = QueryRetrieveError.unknownMoveDestination(aeTitle: "BAD_AE")
        XCTAssertTrue(error.description.contains("BAD_AE"))
    }

    func test_subOperationFailed_description() {
        let error = QueryRetrieveError.subOperationFailed(completed: 5, failed: 2, warning: 1)
        XCTAssertTrue(error.description.contains("5"))
        XCTAssertTrue(error.description.contains("2"))
    }

    func test_noMatchesFound_description() {
        let error = QueryRetrieveError.noMatchesFound
        XCTAssertTrue(error.description.contains("No matching"))
    }

    func test_queryCancelled_description() {
        let error = QueryRetrieveError.queryCancelled
        XCTAssertTrue(error.description.contains("cancelled"))
    }

    func test_instanceFileNotFound_description() {
        let error = QueryRetrieveError.instanceFileNotFound(sopInstanceUID: "1.2.3", path: "/archive/1.2.3.dcm")
        XCTAssertTrue(error.description.contains("1.2.3"))
        XCTAssertTrue(error.description.contains("/archive"))
    }

    func test_databaseError_description() {
        struct TestError: Error, CustomStringConvertible { var description: String { "db fail" } }
        let error = QueryRetrieveError.databaseError(underlying: TestError())
        XCTAssertTrue(error.description.contains("db fail"))
    }
}

// MARK: - DICOMListenerConfiguration Q/R Tests

final class DICOMListenerConfigurationQRTests: XCTestCase {

    func test_defaultAcceptedSOPClasses_includesQueryRetrieveFindUIDs() {
        let classes = DICOMListenerConfiguration.defaultAcceptedSOPClasses
        XCTAssertTrue(classes.contains(patientRootQueryRetrieveFindSOPClassUID))
        XCTAssertTrue(classes.contains(studyRootQueryRetrieveFindSOPClassUID))
    }

    func test_defaultAcceptedSOPClasses_includesQueryRetrieveMoveUIDs() {
        let classes = DICOMListenerConfiguration.defaultAcceptedSOPClasses
        XCTAssertTrue(classes.contains(patientRootQueryRetrieveMoveSOPClassUID))
        XCTAssertTrue(classes.contains(studyRootQueryRetrieveMoveSOPClassUID))
    }

    func test_defaultAcceptedSOPClasses_includesQueryRetrieveGetUIDs() {
        let classes = DICOMListenerConfiguration.defaultAcceptedSOPClasses
        XCTAssertTrue(classes.contains(patientRootQueryRetrieveGetSOPClassUID))
        XCTAssertTrue(classes.contains(studyRootQueryRetrieveGetSOPClassUID))
    }

    func test_defaultAcceptedSOPClasses_stillIncludesVerification() {
        let classes = DICOMListenerConfiguration.defaultAcceptedSOPClasses
        XCTAssertTrue(classes.contains(verificationSOPClassUID))
    }
}

// MARK: - FindSCUResult Tests

final class FindSCUResultTests: XCTestCase {

    func test_findSCUResult_properties_arePreserved() {
        let result = FindSCUResult(
            matches: [Data([0x01]), Data([0x02])],
            queryLevel: .study,
            roundTripTime: 0.123,
            remoteAETitle: "REMOTE",
            host: "192.168.1.1",
            port: 11112
        )

        XCTAssertEqual(result.matches.count, 2)
        XCTAssertEqual(result.queryLevel, .study)
        XCTAssertEqual(result.roundTripTime, 0.123, accuracy: 0.001)
        XCTAssertEqual(result.remoteAETitle, "REMOTE")
        XCTAssertEqual(result.host, "192.168.1.1")
        XCTAssertEqual(result.port, 11112)
        XCTAssertTrue(result.hasMatches)
    }

    func test_findSCUResult_emptyMatches_hasMatchesIsFalse() {
        let result = FindSCUResult(
            matches: [],
            queryLevel: .patient,
            roundTripTime: 0.1,
            remoteAETitle: "AE",
            host: "localhost",
            port: 104
        )
        XCTAssertFalse(result.hasMatches)
    }

    func test_findSCUResult_description_containsMatchCount() {
        let result = FindSCUResult(
            matches: [Data([0x01])],
            queryLevel: .series,
            roundTripTime: 0.05,
            remoteAETitle: "AE",
            host: "h",
            port: 1
        )
        XCTAssertTrue(result.description.contains("1 match"))
        XCTAssertTrue(result.description.contains("C-FIND"))
    }
}

// MARK: - MoveSCUResult Tests

final class MoveSCUResultTests: XCTestCase {

    func test_moveSCUResult_properties_arePreserved() {
        let result = MoveSCUResult(
            success: true,
            status: .success,
            completed: 5,
            failed: 0,
            warning: 1,
            roundTripTime: 1.5,
            remoteAETitle: "REMOTE",
            moveDestination: "LOCAL",
            host: "10.0.0.1",
            port: 11112
        )

        XCTAssertTrue(result.success)
        XCTAssertTrue(result.status.isSuccess)
        XCTAssertEqual(result.completed, 5)
        XCTAssertEqual(result.failed, 0)
        XCTAssertEqual(result.warning, 1)
        XCTAssertEqual(result.roundTripTime, 1.5, accuracy: 0.01)
        XCTAssertEqual(result.remoteAETitle, "REMOTE")
        XCTAssertEqual(result.moveDestination, "LOCAL")
        XCTAssertEqual(result.host, "10.0.0.1")
        XCTAssertEqual(result.port, 11112)
    }

    func test_moveSCUResult_description_containsStatus() {
        let success = MoveSCUResult(
            success: true, status: .success, completed: 1, failed: 0, warning: 0,
            roundTripTime: 0.1, remoteAETitle: "AE", moveDestination: "D", host: "h", port: 1
        )
        XCTAssertTrue(success.description.contains("SUCCESS"))

        let failure = MoveSCUResult(
            success: false, status: .failedUnableToProcess, completed: 0, failed: 1, warning: 0,
            roundTripTime: 0.1, remoteAETitle: "AE", moveDestination: "D", host: "h", port: 1
        )
        XCTAssertTrue(failure.description.contains("FAILED"))
    }

    func test_moveSCUResult_equatable() {
        let a = MoveSCUResult(
            success: true, status: .success, completed: 1, failed: 0, warning: 0,
            roundTripTime: 0.1, remoteAETitle: "AE", moveDestination: "D", host: "h", port: 1
        )
        let b = MoveSCUResult(
            success: true, status: .success, completed: 1, failed: 0, warning: 0,
            roundTripTime: 0.1, remoteAETitle: "AE", moveDestination: "D", host: "h", port: 1
        )
        XCTAssertEqual(a, b)
    }
}

// MARK: - GetSCUResult Tests

final class GetSCUResultTests: XCTestCase {

    func test_getSCUResult_properties_arePreserved() {
        let result = GetSCUResult(
            success: true,
            status: .success,
            completed: 3,
            failed: 0,
            warning: 0,
            roundTripTime: 0.8,
            remoteAETitle: "REMOTE",
            host: "192.168.1.1",
            port: 11112
        )

        XCTAssertTrue(result.success)
        XCTAssertTrue(result.status.isSuccess)
        XCTAssertEqual(result.completed, 3)
        XCTAssertEqual(result.failed, 0)
        XCTAssertEqual(result.warning, 0)
        XCTAssertEqual(result.roundTripTime, 0.8, accuracy: 0.01)
        XCTAssertEqual(result.remoteAETitle, "REMOTE")
    }

    func test_getSCUResult_description_containsStatus() {
        let success = GetSCUResult(
            success: true, status: .success, completed: 1, failed: 0, warning: 0,
            roundTripTime: 0.1, remoteAETitle: "AE", host: "h", port: 1
        )
        XCTAssertTrue(success.description.contains("SUCCESS"))

        let failure = GetSCUResult(
            success: false, status: .failedUnableToProcess, completed: 0, failed: 1, warning: 0,
            roundTripTime: 0.1, remoteAETitle: "AE", host: "h", port: 1
        )
        XCTAssertTrue(failure.description.contains("FAILED"))
    }

    func test_getSCUResult_equatable() {
        let a = GetSCUResult(
            success: true, status: .success, completed: 1, failed: 0, warning: 0,
            roundTripTime: 0.1, remoteAETitle: "AE", host: "h", port: 1
        )
        let b = GetSCUResult(
            success: true, status: .success, completed: 1, failed: 0, warning: 0,
            roundTripTime: 0.1, remoteAETitle: "AE", host: "h", port: 1
        )
        XCTAssertEqual(a, b)
    }
}

// MARK: - C-FIND SCP/SCU Integration Tests

final class CFindIntegrationTests: XCTestCase {

    func test_cFindSCPSCU_endToEnd_emptyArchive_returnsNoMatches() async throws {
        let logger = Logger(label: "test.cfind.integration")
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 2)

        // Create a StorageActor
        let tempDir = NSTemporaryDirectory() + "mayam_test_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let storageActor = StorageActor(
            archivePath: tempDir,
            checksumEnabled: false,
            logger: MayamLogger(label: "test.integration")
        )

        // Create SCPs
        let qrSCP = QueryRetrieveSCP(storageActor: storageActor, logger: logger)
        let dispatcher = SCPDispatcher(queryRetrieveSCP: qrSCP)

        // Configure and start listener with Q/R SOP Classes
        let config = DICOMListenerConfiguration(aeTitle: "QR_SCP", port: 0)
        let listener = DICOMListener(
            configuration: config,
            dispatcher: dispatcher,
            logger: logger,
            eventLoopGroup: eventLoopGroup
        )

        try await listener.start()

        guard let actualPort = await listener.localPort() else {
            XCTFail("Failed to get bound port")
            await listener.stop()
            try await eventLoopGroup.shutdownGracefully()
            return
        }

        // Build a study-level identifier
        var identifier = Data()
        // Query/Retrieve Level = STUDY
        identifier.append(contentsOf: [0x08, 0x00, 0x52, 0x00]) // tag
        let levelValue = "STUDY ".data(using: .ascii)!
        var levelLength = UInt32(levelValue.count).littleEndian
        identifier.append(Data(bytes: &levelLength, count: 4))
        identifier.append(levelValue)

        // Perform a C-FIND SCU against the running SCP
        let scu = FindSCU(logger: logger)

        let result = try await scu.find(
            host: "127.0.0.1",
            port: actualPort,
            callingAE: "TEST_SCU",
            calledAE: "QR_SCP",
            informationModel: .studyRoot,
            queryLevel: .study,
            identifier: identifier,
            timeout: 10
        )

        // Empty archive should return no matches
        XCTAssertEqual(result.matches.count, 0)
        XCTAssertFalse(result.hasMatches)
        XCTAssertEqual(result.queryLevel, QueryLevel.study)
        XCTAssertEqual(result.remoteAETitle, "QR_SCP")
        XCTAssertEqual(result.host, "127.0.0.1")
        XCTAssertEqual(result.port, actualPort)
        XCTAssertGreaterThan(result.roundTripTime, 0)

        // Clean up
        await listener.stop()
        try await eventLoopGroup.shutdownGracefully()
    }
}

// MARK: - StoreSCUResult Tests (Extended)

final class StoreSCUResultExtendedTests: XCTestCase {

    func test_storeSCUResult_description_containsSOPInstanceUID() {
        let result = StoreSCUResult(
            success: true,
            status: .success,
            sopClassUID: "1.2.840.10008.5.1.4.1.1.2",
            sopInstanceUID: "1.2.3.4.5",
            roundTripTime: 0.1,
            remoteAETitle: "AE",
            host: "h",
            port: 1
        )
        XCTAssertTrue(result.description.contains("1.2.3.4.5"))
    }
}
