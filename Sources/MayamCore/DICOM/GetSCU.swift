// SPDX-License-Identifier: (see LICENSE)
// Mayam — Get SCU (C-GET Service Class User)

import Foundation
import NIOCore
import NIOPosix
import Logging
import DICOMNetwork

/// DICOM Get Service Class User (C-GET SCU).
///
/// Sends a C-GET request to a remote DICOM SCP to retrieve DICOM objects
/// directly on the same association. Unlike C-MOVE, no separate outbound
/// connection is required — the SCP sends the objects back as C-STORE
/// sub-operations on the existing association.
///
/// Reference: DICOM PS3.4 Section C.4.3 — C-GET Service
/// Reference: DICOM PS3.7 Section 9.1.3 — C-GET Service
///
/// ## Usage
///
/// ```swift
/// let scu = GetSCU(logger: logger)
/// let result = try await scu.get(
///     host: "pacs.hospital.com",
///     port: 11112,
///     callingAE: "MAYAM",
///     calledAE: "REMOTE_PACS",
///     identifier: identifierData
/// )
/// print("Retrieved \(result.completed) objects")
/// ```
public struct GetSCU: Sendable {

    // MARK: - Stored Properties

    /// Logger for SCU events.
    private let logger: Logger

    // MARK: - Initialiser

    /// Creates a new Get SCU.
    ///
    /// - Parameter logger: Logger instance for SCU events.
    public init(logger: Logger) {
        self.logger = logger
    }

    // MARK: - Public Methods

    /// Performs a C-GET request against a remote DICOM SCP.
    ///
    /// - Parameters:
    ///   - host: The remote host address (IP or hostname).
    ///   - port: The remote DICOM port (default: 11112).
    ///   - callingAE: The local AE Title.
    ///   - calledAE: The remote AE Title.
    ///   - informationModel: The Query/Retrieve information model (default: `.studyRoot`).
    ///   - identifier: The query identifier data set specifying which objects to retrieve.
    ///   - timeout: Connection timeout in seconds (default: 30).
    /// - Returns: A ``GetSCUResult`` describing the operation outcome.
    /// - Throws: If the connection or protocol exchange fails.
    public func get(
        host: String,
        port: Int = 11112,
        callingAE: String,
        calledAE: String,
        informationModel: QueryRetrieveInformationModel = .studyRoot,
        identifier: Data,
        timeout: TimeInterval = 30
    ) async throws -> GetSCUResult {
        let startTime = Date()
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let sopClassUID = informationModel.getSOPClassUID

        logger.info("C-GET SCU: connecting to \(host):\(port) (called AE: '\(calledAE)')")

        let handler = GetSCUHandler(
            callingAE: callingAE,
            calledAE: calledAE,
            sopClassUID: sopClassUID,
            identifier: identifier,
            logger: logger
        )

        let bootstrap = ClientBootstrap(group: eventLoopGroup)
            .channelOption(.socketOption(.so_reuseaddr), value: 1)
            .connectTimeout(.seconds(Int64(timeout)))
            .channelInitializer { channel in
                channel.pipeline.addHandlers([
                    ByteToMessageHandler(PDUFrameDecoder()),
                    handler
                ])
            }

        let channel = try await bootstrap.connect(host: host, port: port).get()
        let (success, status, completed, failed, warning) = try await handler.waitForResult()
        try? await channel.close()
        try await eventLoopGroup.shutdownGracefully()

        let roundTripTime = Date().timeIntervalSince(startTime)
        return GetSCUResult(
            success: success,
            status: status,
            completed: completed,
            failed: failed,
            warning: warning,
            roundTripTime: roundTripTime,
            remoteAETitle: calledAE,
            host: host,
            port: port
        )
    }
}

// MARK: - GetSCUResult

/// The result of a C-GET SCU operation.
public struct GetSCUResult: Sendable, Equatable {

    /// Whether the C-GET operation completed successfully.
    public let success: Bool

    /// The DIMSE status returned by the remote SCP.
    public let status: DIMSEStatus

    /// Number of completed sub-operations.
    public let completed: UInt16

    /// Number of failed sub-operations.
    public let failed: UInt16

    /// Number of warning sub-operations.
    public let warning: UInt16

    /// Round-trip time for the complete get operation, in seconds.
    public let roundTripTime: TimeInterval

    /// The remote Application Entity title.
    public let remoteAETitle: String

    /// The remote host address.
    public let host: String

    /// The remote port number.
    public let port: Int

    /// Creates a get SCU result.
    public init(
        success: Bool,
        status: DIMSEStatus,
        completed: UInt16,
        failed: UInt16,
        warning: UInt16,
        roundTripTime: TimeInterval,
        remoteAETitle: String,
        host: String,
        port: Int
    ) {
        self.success = success
        self.status = status
        self.completed = completed
        self.failed = failed
        self.warning = warning
        self.roundTripTime = roundTripTime
        self.remoteAETitle = remoteAETitle
        self.host = host
        self.port = port
    }
}

extension GetSCUResult: CustomStringConvertible {
    public var description: String {
        let statusStr = success ? "SUCCESS" : "FAILED"
        return "C-GET \(statusStr) from \(remoteAETitle)@\(host):\(port) " +
               "completed=\(completed) failed=\(failed) rtt=\(String(format: "%.3f", roundTripTime))s"
    }
}

// MARK: - GetSCU Channel Handler

/// NIO channel handler implementing the C-GET SCU protocol exchange.
///
/// > Concurrency: Marked `@unchecked Sendable` because all mutable state is
/// > accessed exclusively on the NIO EventLoop thread.
final class GetSCUHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private enum State {
        case connecting
        case awaitingAssociateAccept
        case awaitingCGetResponse
        case awaitingReleaseResponse
        case completed
    }

    private let callingAE: String
    private let calledAE: String
    private let sopClassUID: String
    private let identifier: Data
    private let logger: Logger

    private var state: State = .connecting
    private let assembler = MessageAssembler()
    private var negotiatedMaxPDUSize: UInt32 = DICOMListenerConfiguration.defaultMaxPDUSize
    private var lastCompleted: UInt16 = 0
    private var lastFailed: UInt16 = 0
    private var lastWarning: UInt16 = 0

    private var resultContinuation: CheckedContinuation<(Bool, DIMSEStatus, UInt16, UInt16, UInt16), any Error>?

    init(
        callingAE: String,
        calledAE: String,
        sopClassUID: String,
        identifier: Data,
        logger: Logger
    ) {
        self.callingAE = callingAE
        self.calledAE = calledAE
        self.sopClassUID = sopClassUID
        self.identifier = identifier
        self.logger = logger
    }

    func waitForResult() async throws -> (Bool, DIMSEStatus, UInt16, UInt16, UInt16) {
        try await withCheckedThrowingContinuation { self.resultContinuation = $0 }
    }

    // MARK: - NIO Handlers

    func channelActive(context: ChannelHandlerContext) {
        sendAssociateRequest(context: context)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = Self.unwrapInboundIn(data)

        guard let pduTypeByte = buffer.getInteger(at: buffer.readerIndex, as: UInt8.self) else {
            completeWithError(GetSCUError.invalidResponse)
            context.close(promise: nil)
            return
        }

        switch pduTypeByte {
        case 0x02: handleAssociateAccept(context: context, buffer: &buffer)
        case 0x03:
            logger.warning("C-GET SCU: association rejected")
            completeWithResult(false, status: .failedUnableToProcess)
            context.close(promise: nil)
        case 0x04: handleDataTransfer(context: context, buffer: &buffer)
        case 0x06:
            logger.debug("C-GET SCU: A-RELEASE-RP received")
            context.close(promise: nil)
        case 0x07:
            logger.warning("C-GET SCU: A-ABORT received")
            completeWithResult(false, status: .failedUnableToProcess)
            context.close(promise: nil)
        default:
            logger.warning("C-GET SCU: unexpected PDU type 0x\(String(pduTypeByte, radix: 16))")
            completeWithResult(false, status: .failedUnableToProcess)
            context.close(promise: nil)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        logger.error("C-GET SCU: connection error: \(error)")
        completeWithError(error)
        context.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        if state != .completed {
            completeWithResult(false, status: .failedUnableToProcess)
        }
        context.fireChannelInactive()
    }

    // MARK: - Protocol Exchange

    private func sendAssociateRequest(context: ChannelHandlerContext) {
        state = .awaitingAssociateAccept
        do {
            let presentationContext = try PresentationContext(
                id: 1,
                abstractSyntax: sopClassUID,
                transferSyntaxes: [
                    explicitVRLittleEndianTransferSyntaxUID,
                    implicitVRLittleEndianTransferSyntaxUID
                ]
            )

            let requestPDU = AssociateRequestPDU(
                calledAETitle: try AETitle(calledAE),
                callingAETitle: try AETitle(callingAE),
                presentationContexts: [presentationContext],
                maxPDUSize: DICOMListenerConfiguration.defaultMaxPDUSize,
                implementationClassUID: DICOMListenerConfiguration.defaultImplementationClassUID,
                implementationVersionName: DICOMListenerConfiguration.defaultImplementationVersionName
            )

            let encoded = try requestPDU.encode()
            var outBuffer = context.channel.allocator.buffer(capacity: encoded.count)
            outBuffer.writeBytes(encoded)
            context.writeAndFlush(Self.wrapOutboundOut(outBuffer), promise: nil)
            logger.debug("C-GET SCU: A-ASSOCIATE-RQ sent to '\(calledAE)'")
        } catch {
            logger.error("C-GET SCU: failed to send A-ASSOCIATE-RQ: \(error)")
            completeWithError(error)
            context.close(promise: nil)
        }
    }

    private func handleAssociateAccept(context: ChannelHandlerContext, buffer: inout ByteBuffer) {
        let data = Data(buffer.readableBytesView)
        do {
            let decoded = try PDUDecoder.decode(from: data)
            guard let acceptPDU = decoded as? AssociateAcceptPDU else {
                completeWithResult(false, status: .failedUnableToProcess)
                context.close(promise: nil)
                return
            }

            guard acceptPDU.acceptedContextIDs.contains(1) else {
                logger.warning("C-GET SCU: SOP class not accepted by remote SCP")
                sendAbort(context: context)
                completeWithResult(false, status: .failedUnableToProcess)
                return
            }

            if acceptPDU.maxPDUSize > 0 {
                negotiatedMaxPDUSize = min(acceptPDU.maxPDUSize, DICOMListenerConfiguration.defaultMaxPDUSize)
            }

            logger.debug("C-GET SCU: association accepted by '\(calledAE)'")
            state = .awaitingCGetResponse
            sendCGetRequest(context: context)
        } catch {
            logger.error("C-GET SCU: failed to decode A-ASSOCIATE-AC: \(error)")
            completeWithResult(false, status: .failedUnableToProcess)
            context.close(promise: nil)
        }
    }

    private func sendCGetRequest(context: ChannelHandlerContext) {
        let request = CGetRequest(
            messageID: 1,
            affectedSOPClassUID: sopClassUID,
            presentationContextID: 1
        )

        let fragmenter = MessageFragmenter(maxPDUSize: negotiatedMaxPDUSize)
        let pdus = fragmenter.fragmentMessage(
            commandSet: request.commandSet,
            dataSet: identifier,
            presentationContextID: 1
        )

        do {
            for pdu in pdus {
                let encoded = try pdu.encode()
                var outBuffer = context.channel.allocator.buffer(capacity: encoded.count)
                outBuffer.writeBytes(encoded)
                context.writeAndFlush(Self.wrapOutboundOut(outBuffer), promise: nil)
            }
            logger.debug("C-GET SCU: C-GET-RQ sent (\(identifier.count) bytes identifier)")
        } catch {
            logger.error("C-GET SCU: failed to send C-GET-RQ: \(error)")
            completeWithError(error)
            context.close(promise: nil)
        }
    }

    private func handleDataTransfer(context: ChannelHandlerContext, buffer: inout ByteBuffer) {
        let data = Data(buffer.readableBytesView)
        do {
            let decoded = try PDUDecoder.decode(from: data)
            guard let dataPDU = decoded as? DataTransferPDU else { return }

            if let message = try assembler.addPDVs(from: dataPDU),
               let response = message.asCGetResponse() {
                if response.status.isPending {
                    lastCompleted = response.numberOfCompletedSuboperations ?? lastCompleted
                    lastFailed = response.numberOfFailedSuboperations ?? lastFailed
                    lastWarning = response.numberOfWarningSuboperations ?? lastWarning
                    logger.debug("C-GET SCU: pending — completed=\(lastCompleted) failed=\(lastFailed)")
                } else {
                    let success = response.status.isSuccess || response.status.isWarning
                    lastCompleted = response.numberOfCompletedSuboperations ?? lastCompleted
                    lastFailed = response.numberOfFailedSuboperations ?? lastFailed
                    lastWarning = response.numberOfWarningSuboperations ?? lastWarning
                    state = .awaitingReleaseResponse
                    completeWithResult(success, status: response.status)
                    sendReleaseRequest(context: context)
                }
            }
        } catch {
            logger.error("C-GET SCU: error processing response: \(error)")
            completeWithResult(false, status: .failedUnableToProcess)
            context.close(promise: nil)
        }
    }

    private func sendReleaseRequest(context: ChannelHandlerContext) {
        do {
            let encoded = try ReleaseRequestPDU().encode()
            var outBuffer = context.channel.allocator.buffer(capacity: encoded.count)
            outBuffer.writeBytes(encoded)
            context.writeAndFlush(Self.wrapOutboundOut(outBuffer), promise: nil)
        } catch {
            logger.error("C-GET SCU: failed to send A-RELEASE-RQ: \(error)")
            context.close(promise: nil)
        }
    }

    private func sendAbort(context: ChannelHandlerContext) {
        do {
            let encoded = try AbortPDU(source: .serviceUser, reason: 0).encode()
            var outBuffer = context.channel.allocator.buffer(capacity: encoded.count)
            outBuffer.writeBytes(encoded)
            context.writeAndFlush(Self.wrapOutboundOut(outBuffer)).whenComplete { _ in
                context.close(promise: nil)
            }
        } catch {
            context.close(promise: nil)
        }
    }

    // MARK: - Result Completion

    private func completeWithResult(_ success: Bool, status: DIMSEStatus) {
        guard state != .completed else { return }
        state = .completed
        resultContinuation?.resume(returning: (success, status, lastCompleted, lastFailed, lastWarning))
        resultContinuation = nil
    }

    private func completeWithError(_ error: any Error) {
        guard state != .completed else { return }
        state = .completed
        resultContinuation?.resume(throwing: error)
        resultContinuation = nil
    }
}

// MARK: - GetSCU Errors

/// Errors specific to the Get SCU.
public enum GetSCUError: Error, Sendable {
    /// The remote SCP sent an invalid or unexpected response.
    case invalidResponse
}
