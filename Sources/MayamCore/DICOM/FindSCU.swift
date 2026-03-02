// SPDX-License-Identifier: (see LICENSE)
// Mayam — Find SCU (C-FIND Service Class User)

import Foundation
import NIOCore
import NIOPosix
import Logging
import DICOMNetwork

/// DICOM Find Service Class User (C-FIND SCU).
///
/// Sends a C-FIND request to a remote DICOM SCP to query for DICOM objects.
/// This is used for federated queries against upstream PACS nodes.
///
/// Reference: DICOM PS3.4 Annex C — Query/Retrieve Service Class
/// Reference: DICOM PS3.7 Section 9.1.2 — C-FIND Service
///
/// ## Usage
///
/// ```swift
/// let scu = FindSCU(logger: logger)
/// let result = try await scu.find(
///     host: "pacs.hospital.com",
///     port: 11112,
///     callingAE: "MAYAM",
///     calledAE: "REMOTE_PACS",
///     queryLevel: .study,
///     identifier: identifierData
/// )
/// print("Found \(result.matches.count) matches")
/// ```
public struct FindSCU: Sendable {

    // MARK: - Stored Properties

    /// Logger for SCU events.
    private let logger: Logger

    // MARK: - Initialiser

    /// Creates a new Find SCU.
    ///
    /// - Parameter logger: Logger instance for SCU events.
    public init(logger: Logger) {
        self.logger = logger
    }

    // MARK: - Public Methods

    /// Performs a C-FIND query against a remote DICOM SCP.
    ///
    /// - Parameters:
    ///   - host: The remote host address (IP or hostname).
    ///   - port: The remote DICOM port (default: 11112).
    ///   - callingAE: The local AE Title.
    ///   - calledAE: The remote AE Title.
    ///   - informationModel: The Query/Retrieve information model (default: `.studyRoot`).
    ///   - queryLevel: The query level (default: `.study`).
    ///   - identifier: The query identifier data set containing matching keys.
    ///   - timeout: Connection timeout in seconds (default: 30).
    /// - Returns: A ``FindSCUResult`` describing the query outcome.
    /// - Throws: If the connection or protocol exchange fails.
    public func find(
        host: String,
        port: Int = 11112,
        callingAE: String,
        calledAE: String,
        informationModel: QueryRetrieveInformationModel = .studyRoot,
        queryLevel: QueryLevel = .study,
        identifier: Data,
        timeout: TimeInterval = 30
    ) async throws -> FindSCUResult {
        let startTime = Date()
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let sopClassUID = informationModel.findSOPClassUID

        logger.info("C-FIND SCU: connecting to \(host):\(port) (called AE: '\(calledAE)', level: \(queryLevel))")

        let handler = FindSCUHandler(
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
        let matches = try await handler.waitForResult()
        try? await channel.close()
        try await eventLoopGroup.shutdownGracefully()

        let roundTripTime = Date().timeIntervalSince(startTime)
        return FindSCUResult(
            matches: matches,
            queryLevel: queryLevel,
            roundTripTime: roundTripTime,
            remoteAETitle: calledAE,
            host: host,
            port: port
        )
    }
}

// MARK: - FindSCUResult

/// The result of a C-FIND SCU operation.
public struct FindSCUResult: Sendable {

    /// The matched data sets returned by the remote SCP.
    public let matches: [Data]

    /// The query level used for the query.
    public let queryLevel: QueryLevel

    /// Round-trip time for the complete query operation, in seconds.
    public let roundTripTime: TimeInterval

    /// The remote Application Entity title.
    public let remoteAETitle: String

    /// The remote host address.
    public let host: String

    /// The remote port number.
    public let port: Int

    /// Whether matches were found.
    public var hasMatches: Bool { !matches.isEmpty }

    /// Creates a find SCU result.
    public init(
        matches: [Data],
        queryLevel: QueryLevel,
        roundTripTime: TimeInterval,
        remoteAETitle: String,
        host: String,
        port: Int
    ) {
        self.matches = matches
        self.queryLevel = queryLevel
        self.roundTripTime = roundTripTime
        self.remoteAETitle = remoteAETitle
        self.host = host
        self.port = port
    }
}

extension FindSCUResult: CustomStringConvertible {
    public var description: String {
        "C-FIND \(matches.count) match(es) from \(remoteAETitle)@\(host):\(port) " +
        "level=\(queryLevel) rtt=\(String(format: "%.3f", roundTripTime))s"
    }
}

// MARK: - FindSCU Channel Handler

/// NIO channel handler implementing the C-FIND SCU protocol exchange.
///
/// Performs outbound association negotiation, sends a C-FIND request with the
/// query identifier, collects pending matches, then releases the association.
///
/// > Concurrency: Marked `@unchecked Sendable` because all mutable state is
/// > accessed exclusively on the NIO EventLoop thread, as guaranteed by NIO's
/// > threading model.
final class FindSCUHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    // MARK: - Private State

    private enum State {
        case connecting
        case awaitingAssociateAccept
        case awaitingCFindResponse
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
    private var matches: [Data] = []

    private var resultContinuation: CheckedContinuation<[Data], any Error>?

    // MARK: - Initialiser

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

    /// Awaits the completion of the C-FIND exchange.
    ///
    /// - Returns: Array of data sets representing pending matches.
    func waitForResult() async throws -> [Data] {
        try await withCheckedThrowingContinuation { self.resultContinuation = $0 }
    }

    // MARK: - NIO Handlers

    func channelActive(context: ChannelHandlerContext) {
        sendAssociateRequest(context: context)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = Self.unwrapInboundIn(data)

        guard let pduTypeByte = buffer.getInteger(at: buffer.readerIndex, as: UInt8.self) else {
            completeWithError(FindSCUError.invalidResponse)
            context.close(promise: nil)
            return
        }

        switch pduTypeByte {
        case 0x02: handleAssociateAccept(context: context, buffer: &buffer)
        case 0x03:
            logger.warning("C-FIND SCU: association rejected by remote SCP")
            completeWithResult([])
            context.close(promise: nil)
        case 0x04: handleDataTransfer(context: context, buffer: &buffer)
        case 0x06:
            logger.debug("C-FIND SCU: A-RELEASE-RP received")
            context.close(promise: nil)
        case 0x07:
            logger.warning("C-FIND SCU: A-ABORT received from remote SCP")
            completeWithResult([])
            context.close(promise: nil)
        default:
            logger.warning("C-FIND SCU: unexpected PDU type 0x\(String(pduTypeByte, radix: 16))")
            completeWithResult([])
            context.close(promise: nil)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        logger.error("C-FIND SCU: connection error: \(error)")
        completeWithError(error)
        context.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        if state != .completed {
            completeWithResult([])
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
            logger.debug("C-FIND SCU: A-ASSOCIATE-RQ sent to '\(calledAE)'")
        } catch {
            logger.error("C-FIND SCU: failed to send A-ASSOCIATE-RQ: \(error)")
            completeWithError(error)
            context.close(promise: nil)
        }
    }

    private func handleAssociateAccept(context: ChannelHandlerContext, buffer: inout ByteBuffer) {
        let data = Data(buffer.readableBytesView)
        do {
            let decoded = try PDUDecoder.decode(from: data)
            guard let acceptPDU = decoded as? AssociateAcceptPDU else {
                completeWithResult([])
                context.close(promise: nil)
                return
            }

            guard acceptPDU.acceptedContextIDs.contains(1) else {
                logger.warning("C-FIND SCU: SOP class '\(sopClassUID)' not accepted by remote SCP")
                sendAbort(context: context)
                completeWithResult([])
                return
            }

            if acceptPDU.maxPDUSize > 0 {
                negotiatedMaxPDUSize = min(acceptPDU.maxPDUSize, DICOMListenerConfiguration.defaultMaxPDUSize)
            }

            logger.debug("C-FIND SCU: association accepted by '\(calledAE)'")
            state = .awaitingCFindResponse
            sendCFindRequest(context: context)
        } catch {
            logger.error("C-FIND SCU: failed to decode A-ASSOCIATE-AC: \(error)")
            completeWithResult([])
            context.close(promise: nil)
        }
    }

    private func sendCFindRequest(context: ChannelHandlerContext) {
        let request = CFindRequest(
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
            logger.debug("C-FIND SCU: C-FIND-RQ sent (\(identifier.count) bytes identifier)")
        } catch {
            logger.error("C-FIND SCU: failed to send C-FIND-RQ: \(error)")
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
               let response = message.asCFindResponse() {
                if response.status.isPending {
                    // Pending — collect the data set
                    if let dataSet = message.dataSet {
                        matches.append(dataSet)
                    }
                    logger.debug("C-FIND SCU: pending match received (total: \(matches.count))")
                } else if response.status.isSuccess || response.status.isCancel {
                    // Final response — complete and release
                    logger.debug("C-FIND SCU: C-FIND-RSP received (final), \(matches.count) match(es)")
                    state = .awaitingReleaseResponse
                    completeWithResult(matches)
                    sendReleaseRequest(context: context)
                } else {
                    // Failure
                    logger.warning("C-FIND SCU: query failed with status \(response.status)")
                    completeWithResult(matches)
                    sendReleaseRequest(context: context)
                }
            }
        } catch {
            logger.error("C-FIND SCU: error processing response: \(error)")
            completeWithResult(matches)
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
            logger.error("C-FIND SCU: failed to send A-RELEASE-RQ: \(error)")
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

    private func completeWithResult(_ result: [Data]) {
        guard state != .completed else { return }
        state = .completed
        resultContinuation?.resume(returning: result)
        resultContinuation = nil
    }

    private func completeWithError(_ error: any Error) {
        guard state != .completed else { return }
        state = .completed
        resultContinuation?.resume(throwing: error)
        resultContinuation = nil
    }
}

// MARK: - FindSCU Errors

/// Errors specific to the Find SCU.
public enum FindSCUError: Error, Sendable {
    /// The remote SCP sent an invalid or unexpected response.
    case invalidResponse
}
