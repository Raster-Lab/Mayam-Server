// SPDX-License-Identifier: (see LICENSE)
// Mayam — Move SCU (C-MOVE Service Class User)

import Foundation
import NIOCore
import NIOPosix
import Logging
import DICOMNetwork

/// DICOM Move Service Class User (C-MOVE SCU).
///
/// Sends a C-MOVE request to a remote DICOM SCP to retrieve DICOM objects and
/// route them to a specified destination AE. This is used for federated retrieval
/// and upstream routing.
///
/// Reference: DICOM PS3.4 Section C.4.2 — C-MOVE Service
/// Reference: DICOM PS3.7 Section 9.1.4 — C-MOVE Service
///
/// ## Usage
///
/// ```swift
/// let scu = MoveSCU(logger: logger)
/// let result = try await scu.move(
///     host: "pacs.hospital.com",
///     port: 11112,
///     callingAE: "MAYAM",
///     calledAE: "REMOTE_PACS",
///     moveDestination: "LOCAL_STORE",
///     identifier: identifierData
/// )
/// print("Move completed: \(result.completed) objects")
/// ```
public struct MoveSCU: Sendable {

    // MARK: - Stored Properties

    /// Logger for SCU events.
    private let logger: Logger

    // MARK: - Initialiser

    /// Creates a new Move SCU.
    ///
    /// - Parameter logger: Logger instance for SCU events.
    public init(logger: Logger) {
        self.logger = logger
    }

    // MARK: - Public Methods

    /// Performs a C-MOVE request against a remote DICOM SCP.
    ///
    /// - Parameters:
    ///   - host: The remote host address (IP or hostname).
    ///   - port: The remote DICOM port (default: 11112).
    ///   - callingAE: The local AE Title.
    ///   - calledAE: The remote AE Title.
    ///   - informationModel: The Query/Retrieve information model (default: `.studyRoot`).
    ///   - moveDestination: The AE Title of the destination to move objects to.
    ///   - identifier: The query identifier data set specifying which objects to move.
    ///   - timeout: Connection timeout in seconds (default: 30).
    /// - Returns: A ``MoveSCUResult`` describing the operation outcome.
    /// - Throws: If the connection or protocol exchange fails.
    public func move(
        host: String,
        port: Int = 11112,
        callingAE: String,
        calledAE: String,
        informationModel: QueryRetrieveInformationModel = .studyRoot,
        moveDestination: String,
        identifier: Data,
        timeout: TimeInterval = 30
    ) async throws -> MoveSCUResult {
        let startTime = Date()
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let sopClassUID = informationModel.moveSOPClassUID

        logger.info("C-MOVE SCU: connecting to \(host):\(port) (called AE: '\(calledAE)', dest: '\(moveDestination)')")

        let handler = MoveSCUHandler(
            callingAE: callingAE,
            calledAE: calledAE,
            sopClassUID: sopClassUID,
            moveDestination: moveDestination,
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
        return MoveSCUResult(
            success: success,
            status: status,
            completed: completed,
            failed: failed,
            warning: warning,
            roundTripTime: roundTripTime,
            remoteAETitle: calledAE,
            moveDestination: moveDestination,
            host: host,
            port: port
        )
    }
}

// MARK: - MoveSCUResult

/// The result of a C-MOVE SCU operation.
public struct MoveSCUResult: Sendable, Equatable {

    /// Whether the C-MOVE operation completed successfully.
    public let success: Bool

    /// The DIMSE status returned by the remote SCP.
    public let status: DIMSEStatus

    /// Number of completed sub-operations.
    public let completed: UInt16

    /// Number of failed sub-operations.
    public let failed: UInt16

    /// Number of warning sub-operations.
    public let warning: UInt16

    /// Round-trip time for the complete move operation, in seconds.
    public let roundTripTime: TimeInterval

    /// The remote Application Entity title.
    public let remoteAETitle: String

    /// The destination AE Title where objects were moved.
    public let moveDestination: String

    /// The remote host address.
    public let host: String

    /// The remote port number.
    public let port: Int

    /// Creates a move SCU result.
    public init(
        success: Bool,
        status: DIMSEStatus,
        completed: UInt16,
        failed: UInt16,
        warning: UInt16,
        roundTripTime: TimeInterval,
        remoteAETitle: String,
        moveDestination: String,
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
        self.moveDestination = moveDestination
        self.host = host
        self.port = port
    }
}

extension MoveSCUResult: CustomStringConvertible {
    public var description: String {
        let statusStr = success ? "SUCCESS" : "FAILED"
        return "C-MOVE \(statusStr) from \(remoteAETitle)@\(host):\(port) → \(moveDestination) " +
               "completed=\(completed) failed=\(failed) rtt=\(String(format: "%.3f", roundTripTime))s"
    }
}

// MARK: - MoveSCU Channel Handler

/// NIO channel handler implementing the C-MOVE SCU protocol exchange.
///
/// > Concurrency: Marked `@unchecked Sendable` because all mutable state is
/// > accessed exclusively on the NIO EventLoop thread.
final class MoveSCUHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private enum State {
        case connecting
        case awaitingAssociateAccept
        case awaitingCMoveResponse
        case awaitingReleaseResponse
        case completed
    }

    private let callingAE: String
    private let calledAE: String
    private let sopClassUID: String
    private let moveDestination: String
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
        moveDestination: String,
        identifier: Data,
        logger: Logger
    ) {
        self.callingAE = callingAE
        self.calledAE = calledAE
        self.sopClassUID = sopClassUID
        self.moveDestination = moveDestination
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
            completeWithError(MoveSCUError.invalidResponse)
            context.close(promise: nil)
            return
        }

        switch pduTypeByte {
        case 0x02: handleAssociateAccept(context: context, buffer: &buffer)
        case 0x03:
            logger.warning("C-MOVE SCU: association rejected")
            completeWithResult(false, status: .failedUnableToProcess)
            context.close(promise: nil)
        case 0x04: handleDataTransfer(context: context, buffer: &buffer)
        case 0x06:
            logger.debug("C-MOVE SCU: A-RELEASE-RP received")
            context.close(promise: nil)
        case 0x07:
            logger.warning("C-MOVE SCU: A-ABORT received")
            completeWithResult(false, status: .failedUnableToProcess)
            context.close(promise: nil)
        default:
            logger.warning("C-MOVE SCU: unexpected PDU type 0x\(String(pduTypeByte, radix: 16))")
            completeWithResult(false, status: .failedUnableToProcess)
            context.close(promise: nil)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        logger.error("C-MOVE SCU: connection error: \(error)")
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
            logger.debug("C-MOVE SCU: A-ASSOCIATE-RQ sent to '\(calledAE)'")
        } catch {
            logger.error("C-MOVE SCU: failed to send A-ASSOCIATE-RQ: \(error)")
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
                logger.warning("C-MOVE SCU: SOP class not accepted by remote SCP")
                sendAbort(context: context)
                completeWithResult(false, status: .failedUnableToProcess)
                return
            }

            if acceptPDU.maxPDUSize > 0 {
                negotiatedMaxPDUSize = min(acceptPDU.maxPDUSize, DICOMListenerConfiguration.defaultMaxPDUSize)
            }

            logger.debug("C-MOVE SCU: association accepted by '\(calledAE)'")
            state = .awaitingCMoveResponse
            sendCMoveRequest(context: context)
        } catch {
            logger.error("C-MOVE SCU: failed to decode A-ASSOCIATE-AC: \(error)")
            completeWithResult(false, status: .failedUnableToProcess)
            context.close(promise: nil)
        }
    }

    private func sendCMoveRequest(context: ChannelHandlerContext) {
        let request = CMoveRequest(
            messageID: 1,
            affectedSOPClassUID: sopClassUID,
            moveDestination: moveDestination,
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
            logger.debug("C-MOVE SCU: C-MOVE-RQ sent (dest='\(moveDestination)')")
        } catch {
            logger.error("C-MOVE SCU: failed to send C-MOVE-RQ: \(error)")
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
               let response = message.asCMoveResponse() {
                if response.status.isPending {
                    lastCompleted = response.numberOfCompletedSuboperations ?? lastCompleted
                    lastFailed = response.numberOfFailedSuboperations ?? lastFailed
                    lastWarning = response.numberOfWarningSuboperations ?? lastWarning
                    logger.debug("C-MOVE SCU: pending — completed=\(lastCompleted) failed=\(lastFailed)")
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
            logger.error("C-MOVE SCU: error processing response: \(error)")
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
            logger.error("C-MOVE SCU: failed to send A-RELEASE-RQ: \(error)")
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

// MARK: - MoveSCU Errors

/// Errors specific to the Move SCU.
public enum MoveSCUError: Error, Sendable {
    /// The remote SCP sent an invalid or unexpected response.
    case invalidResponse
}
