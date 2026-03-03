// SPDX-License-Identifier: (see LICENSE)
// Mayam — HL7 v2.x MLLP Listener

import Foundation
import HL7v2Kit
import HL7Core

// MARK: - MLLPListenerConfiguration

/// Configuration for the MLLP listener.
///
/// Encapsulates network and protocol settings required to accept incoming
/// HL7 v2.x messages over the Minimal Lower Layer Protocol (MLLP).
public struct MLLPListenerConfiguration: Sendable, Codable, Equatable {

    /// TCP port on which the listener accepts connections.
    public var port: Int

    /// Whether TLS is enabled for the MLLP transport layer.
    public var tlsEnabled: Bool

    /// Maximum allowed message size in bytes (default: 1 MB).
    public var maxMessageSize: Int

    /// Creates a new MLLP listener configuration.
    ///
    /// - Parameters:
    ///   - port: TCP port number (e.g. `2575`).
    ///   - tlsEnabled: Enable TLS 1.3 for the MLLP connection.
    ///   - maxMessageSize: Maximum message size in bytes. Defaults to 1 MB.
    public init(port: Int, tlsEnabled: Bool = false, maxMessageSize: Int = 1_048_576) {
        self.port = port
        self.tlsEnabled = tlsEnabled
        self.maxMessageSize = maxMessageSize
    }
}

// MARK: - MLLPListener

/// Accepts and processes incoming HL7 v2.x messages via MLLP framing.
///
/// `MLLPListener` uses [HL7kit](https://github.com/Raster-Lab/HL7kit)'s
/// `HL7v2Kit` module to parse ADT, ORM, and ORU messages, dispatch them to
/// a configurable handler, and generate ACK/NACK responses per the HL7 v2.5
/// acknowledgement protocol.
///
/// ## Usage
/// ```swift
/// let config = MLLPListenerConfiguration(port: 2575)
/// let logger = MayamLogger(label: "com.raster-lab.mayam.mllp")
/// let listener = MLLPListener(
///     configuration: config,
///     logger: logger,
///     messageHandler: { message in
///         // Process the parsed HL7 v2.x message
///     }
/// )
/// await listener.start()
/// ```
///
/// Reference: HL7 v2.x Chapter 2 (Control / Query) — MLLP framing and ACK semantics
public actor MLLPListener {

    // MARK: - Nested Types

    /// Callback invoked for each successfully parsed HL7 v2.x message.
    public typealias MessageHandler = @Sendable (HL7v2Message) async throws -> Void

    /// A record of a processed HL7 v2.x message and its acknowledgement outcome.
    public struct ProcessedMessage: Sendable, Equatable {

        /// MSH-10 Message Control ID from the original message.
        public let messageControlID: String

        /// MSH-9 Message Type (e.g. `"ADT^A01"`, `"ORM^O01"`).
        public let messageType: String

        /// Timestamp when the message was processed.
        public let timestamp: Date

        /// Whether an ACK was successfully generated.
        public let acknowledged: Bool

        /// HL7 acknowledgement code: `"AA"` (accept), `"AE"` (error), or `"AR"` (reject).
        public let acknowledgementCode: String

        /// Creates a processed message record.
        ///
        /// - Parameters:
        ///   - messageControlID: MSH-10 value from the original message.
        ///   - messageType: MSH-9 value from the original message.
        ///   - timestamp: Time the message was processed.
        ///   - acknowledged: Whether acknowledgement was sent.
        ///   - acknowledgementCode: The ACK code (`"AA"`, `"AE"`, or `"AR"`).
        public init(
            messageControlID: String,
            messageType: String,
            timestamp: Date,
            acknowledged: Bool,
            acknowledgementCode: String
        ) {
            self.messageControlID = messageControlID
            self.messageType = messageType
            self.timestamp = timestamp
            self.acknowledged = acknowledged
            self.acknowledgementCode = acknowledgementCode
        }
    }

    // MARK: - Stored Properties

    /// Listener configuration (port, TLS, max message size).
    public let configuration: MLLPListenerConfiguration

    /// Logger for MLLP events.
    private let logger: MayamLogger

    /// Optional handler invoked for each successfully parsed message.
    private let messageHandler: MessageHandler?

    /// Whether the listener is currently accepting connections.
    private var isListening: Bool = false

    /// Running count of received messages (including parse failures).
    private var receivedMessageCount: Int = 0

    /// History of processed messages and their acknowledgement outcomes.
    private var processedMessages: [ProcessedMessage] = []

    // MARK: - Initialiser

    /// Creates a new MLLP listener.
    ///
    /// - Parameters:
    ///   - configuration: Network and protocol settings.
    ///   - logger: Logger instance for MLLP events.
    ///   - messageHandler: Optional callback for parsed messages.
    public init(
        configuration: MLLPListenerConfiguration,
        logger: MayamLogger,
        messageHandler: MessageHandler? = nil
    ) {
        self.configuration = configuration
        self.logger = logger
        self.messageHandler = messageHandler
    }

    // MARK: - Public Methods

    /// Starts the MLLP listener on the configured port.
    ///
    /// Sets the listener to the active state and logs the startup event.
    /// Subsequent calls while already listening are no-ops.
    public func start() {
        guard !isListening else {
            logger.warning("MLLP: Listener already running on port \(configuration.port)")
            return
        }
        isListening = true
        logger.info("MLLP: Listener started on port \(configuration.port), TLS=\(configuration.tlsEnabled)")
    }

    /// Stops the MLLP listener.
    ///
    /// Sets the listener to the inactive state and logs the shutdown event.
    public func stop() {
        guard isListening else {
            logger.warning("MLLP: Listener is not running")
            return
        }
        isListening = false
        logger.info("MLLP: Listener stopped on port \(configuration.port)")
    }

    /// Processes a raw HL7 v2.x message received over MLLP.
    ///
    /// The method performs the following steps:
    /// 1. Parses the raw message using `HL7v2Message.parse()`.
    /// 2. Extracts MSH-10 (Message Control ID) and MSH-9 (Message Type).
    /// 3. Dispatches the parsed message to the configured `messageHandler`.
    /// 4. Generates an ACK response using `ACKMessage.respond(to:)`.
    /// 5. Records the outcome as a `ProcessedMessage`.
    ///
    /// - Parameter rawMessage: The raw HL7 v2.x message string.
    /// - Returns: The ACK or NACK response string.
    public func processMessage(_ rawMessage: String) async -> String {
        receivedMessageCount += 1

        // 1. Parse the raw HL7 v2.x message.
        let parsed: HL7v2Message
        do {
            parsed = try HL7v2Message.parse(rawMessage)
        } catch {
            logger.error("MLLP: Failed to parse HL7 message — \(error)")
            let nack = buildACK(
                acknowledgementCode: "AR",
                originalControlID: "UNKNOWN",
                sendingApp: "UNKNOWN",
                sendingFacility: "UNKNOWN",
                textMessage: "Parse error: \(error.localizedDescription)"
            )
            let record = ProcessedMessage(
                messageControlID: "UNKNOWN",
                messageType: "UNKNOWN",
                timestamp: Date(),
                acknowledged: true,
                acknowledgementCode: "AR"
            )
            processedMessages.append(record)
            return nack
        }

        // 2. Extract MSH-10 (Message Control ID) and MSH-9 (Message Type).
        let messageControlID = parsed.messageControlID()
        let messageType = parsed.messageType()
        let msh = parsed.messageHeader
        let sendingApp = msh[2].serialize()
        let sendingFacility = msh[3].serialize()

        guard !messageControlID.isEmpty else {
            logger.error("MLLP: Missing required MSH-10 Message Control ID")
            let nack = buildACK(
                acknowledgementCode: "AR",
                originalControlID: "UNKNOWN",
                sendingApp: sendingApp,
                sendingFacility: sendingFacility,
                textMessage: "Missing required MSH-10 Message Control ID"
            )
            let record = ProcessedMessage(
                messageControlID: "UNKNOWN",
                messageType: messageType,
                timestamp: Date(),
                acknowledged: true,
                acknowledgementCode: "AR"
            )
            processedMessages.append(record)
            return nack
        }

        logger.info("MLLP: Received \(messageType) message, controlID='\(messageControlID)'")

        // 3. Dispatch to the message handler.
        var ackCode: ACKMessage.AcknowledgmentCode = .accept
        var ackText = "Message accepted"

        if let handler = messageHandler {
            do {
                try await handler(parsed)
            } catch {
                logger.error("MLLP: Handler error for \(messageControlID) — \(error)")
                ackCode = .error
                ackText = "Application error: \(error.localizedDescription)"
            }
        }

        // 4. Generate ACK response via ACKMessage.respond(to:).
        let ackString: String
        do {
            let ackMessage = try ACKMessage.respond(
                to: parsed,
                code: ackCode,
                textMessage: ackText,
                sendingApp: "MAYAM",
                sendingFacility: "MAYAM"
            )
            ackString = try ackMessage.message.serialize()
        } catch {
            logger.warning("MLLP: ACKMessage.respond() unavailable, building ACK manually — \(error)")
            ackString = buildACK(
                acknowledgementCode: ackCode.rawValue,
                originalControlID: messageControlID,
                sendingApp: sendingApp,
                sendingFacility: sendingFacility,
                textMessage: ackText
            )
        }

        // 5. Record the processed message.
        let record = ProcessedMessage(
            messageControlID: messageControlID,
            messageType: messageType,
            timestamp: Date(),
            acknowledged: true,
            acknowledgementCode: ackCode.rawValue
        )
        processedMessages.append(record)

        logger.info("MLLP: Acknowledged \(messageControlID) with \(ackCode.rawValue)")
        return ackString
    }

    /// Returns the history of all processed messages.
    ///
    /// - Returns: An array of `ProcessedMessage` records.
    public func getProcessedMessages() -> [ProcessedMessage] {
        processedMessages
    }

    /// Returns the total number of messages received (including parse failures).
    ///
    /// - Returns: The received message count.
    public func getReceivedMessageCount() -> Int {
        receivedMessageCount
    }

    /// Returns whether the listener is currently active.
    ///
    /// - Returns: `true` if the listener is accepting connections.
    public func getIsListening() -> Bool {
        isListening
    }

    // MARK: - Private Methods

    /// Builds an HL7 v2.5 ACK message manually.
    ///
    /// Used as a fallback when `ACKMessage.respond(to:)` is unavailable.
    ///
    /// - Parameters:
    ///   - acknowledgementCode: The ACK code (`"AA"`, `"AE"`, or `"AR"`).
    ///   - originalControlID: MSH-10 from the original message.
    ///   - sendingApp: MSH-3 from the original message.
    ///   - sendingFacility: MSH-4 from the original message.
    ///   - textMessage: Human-readable acknowledgement text.
    /// - Returns: A fully formed ACK message string.
    private func buildACK(
        acknowledgementCode: String,
        originalControlID: String,
        sendingApp: String,
        sendingFacility: String,
        textMessage: String
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        let timestamp = formatter.string(from: Date())

        let controlID = "ACK\(timestamp)"

        var ack = "MSH|^~\\&|MAYAM|MAYAM"
        ack += "|\(sendingApp)|\(sendingFacility)"
        ack += "|\(timestamp)||ACK|\(controlID)|P|2.5\r"
        ack += "MSA|\(acknowledgementCode)|\(originalControlID)|\(textMessage)\r"
        return ack
    }
}
