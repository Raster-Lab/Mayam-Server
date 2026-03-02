// SPDX-License-Identifier: (see LICENSE)
// Mayam — LDAP Client Integration Tests (in-process mock LDAP server)

import XCTest
import Foundation
import NIOCore
import NIOPosix
@testable import MayamCore

// MARK: - MockLDAPServer

/// A minimal in-process LDAP server that speaks RFC 4511 over a plain TCP
/// socket.  Used exclusively for integration-testing ``LDAPClient``.
///
/// The mock server supports:
/// - Simple BindRequest / BindResponse (success or `invalidCredentials`).
/// - SearchRequest / SearchResultEntry + SearchResultDone (with one
///   hard-coded user entry per username supplied at start-up).
/// - UnbindRequest (triggers channel close).
final class MockLDAPServer: @unchecked Sendable {

    // MARK: - Stored Properties

    private var serverChannel: (any Channel)?
    private let eventLoopGroup: MultiThreadedEventLoopGroup
    /// Valid binds: DN → password.
    private let validBinds: [String: String]
    /// Directory entries keyed by username.
    private let entries: [String: MockLDAPEntry]

    // MARK: - Initialiser

    init(validBinds: [String: String], entries: [String: MockLDAPEntry]) {
        self.validBinds = validBinds
        self.entries = entries
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    // MARK: - Lifecycle

    /// Starts the mock server on an ephemeral port.
    ///
    /// - Returns: The port the server bound to.
    func start() async throws -> Int {
        let validBinds = self.validBinds
        let entries = self.entries
        let server = try await ServerBootstrap(group: eventLoopGroup)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.addHandler(
                    LDAPMockHandler(validBinds: validBinds, entries: entries)
                )
            }
            .bind(host: "127.0.0.1", port: 0)
            .get()
        self.serverChannel = server
        return server.localAddress!.port!
    }

    /// Shuts down the mock server.
    func stop() async {
        try? await serverChannel?.close().get()
        try? await eventLoopGroup.shutdownGracefully()
    }
}

// MARK: - MockLDAPEntry

/// A user entry served by the mock LDAP server.
struct MockLDAPEntry: Sendable {
    let dn: String
    let username: String
    let email: String?
    let displayName: String?
    let groups: [String]

    init(
        dn: String,
        username: String,
        email: String? = nil,
        displayName: String? = nil,
        groups: [String] = []
    ) {
        self.dn = dn
        self.username = username
        self.email = email
        self.displayName = displayName
        self.groups = groups
    }
}

// MARK: - LDAPMockHandler

/// NIO channel handler that implements a minimal LDAP server state machine.
private final class LDAPMockHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private let validBinds: [String: String]
    private let entries: [String: MockLDAPEntry]
    private var accumulated: [UInt8] = []

    init(validBinds: [String: String], entries: [String: MockLDAPEntry]) {
        self.validBinds = validBinds
        self.entries = entries
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buf = unwrapInboundIn(data)
        accumulated += Array(buf.readableBytesView)
        processMessages(context: context)
    }

    private func processMessages(context: ChannelHandlerContext) {
        while let message = extractMessage() {
            handle(message: message, context: context)
        }
    }

    private func extractMessage() -> [UInt8]? {
        guard accumulated.count >= 2 else { return nil }
        guard accumulated[0] == BERTag.sequence else { return nil }
        var offset = 1
        guard let length = try? parseLengthAt(bytes: accumulated, offset: &offset) else { return nil }
        let totalNeeded = offset + length
        guard accumulated.count >= totalNeeded else { return nil }
        let msg = Array(accumulated[0 ..< totalNeeded])
        accumulated.removeFirst(totalNeeded)
        return msg
    }

    private func handle(message: [UInt8], context: ChannelHandlerContext) {
        // Parse LDAPMessage SEQUENCE { messageID INTEGER, protocolOp }
        var offset = 0
        guard let outerContents = try? BERDecoder.readSequence(from: message, offset: &offset) else { return }
        var inner = 0
        guard let msgID = try? BERDecoder.readInteger(from: outerContents, offset: &inner) else { return }
        guard inner < outerContents.count else { return }

        let appTag = outerContents[inner]
        inner += 1
        guard let len = try? parseLengthAt(bytes: outerContents, offset: &inner) else { return }
        guard inner + len <= outerContents.count else { return }
        let payload = Array(outerContents[inner ..< inner + len])

        // APPLICATION 0 = BindRequest
        if appTag == BERTag.application(0) {
            handleBind(messageID: msgID, payload: payload, context: context)
        }
        // APPLICATION 2 (primitive) = UnbindRequest → close
        else if appTag == 0x42 {
            context.close(promise: nil)
        }
        // APPLICATION 3 = SearchRequest
        else if appTag == BERTag.application(3) {
            handleSearch(messageID: msgID, payload: payload, context: context)
        }
    }

    private func handleBind(messageID: Int, payload: [UInt8], context: ChannelHandlerContext) {
        // BindRequest: version INTEGER, name LDAPDN, simple [0] OCTET STRING
        var offset = 0
        _ = try? BERDecoder.readInteger(from: payload, offset: &offset)  // version
        let dn = (try? BERDecoder.readOctetString(from: payload, offset: &offset)) ?? ""

        // Simple auth [0] tag
        var password = ""
        if offset < payload.count {
            let simpleTag = payload[offset]
            offset += 1
            if let pwdLen = try? parseLengthAt(bytes: payload, offset: &offset),
               offset + pwdLen <= payload.count,
               simpleTag == BERTag.contextPrimitive(0) {
                let pwdBytes = Array(payload[offset ..< offset + pwdLen])
                password = String(bytes: pwdBytes, encoding: .utf8) ?? ""
            }
        }

        // Check credentials
        let resultCode: Int
        if let expectedPassword = validBinds[dn], expectedPassword == password {
            resultCode = 0  // success
        } else if dn.isEmpty && password.isEmpty {
            resultCode = 0  // anonymous bind always succeeds in mock
        } else {
            resultCode = 49 // invalidCredentials
        }

        let response = buildLDAPResult(messageID: messageID, applicationTag: 1, resultCode: resultCode)
        write(response, to: context)
    }

    private func handleSearch(messageID: Int, payload: [UInt8], context: ChannelHandlerContext) {
        // We only extract the equality filter value to find the username.
        // A real server would fully parse the filter; this mock scans for the query value.
        var offset = 0
        _ = try? BERDecoder.readOctetString(from: payload, offset: &offset) // baseObject
        _ = try? BERDecoder.readEnumerated(from: payload, offset: &offset)  // scope
        _ = try? BERDecoder.readEnumerated(from: payload, offset: &offset)  // derefAliases
        _ = try? BERDecoder.readInteger(from: payload, offset: &offset)     // sizeLimit
        _ = try? BERDecoder.readInteger(from: payload, offset: &offset)     // timeLimit
        _ = try? BERDecoder.readBoolean(from: payload, offset: &offset)     // typesOnly

        // The filter is [3] CONSTRUCTED (equalityMatch): attr OCTET STRING, value OCTET STRING
        let usernameValue = extractEqualityFilterValue(from: payload, startOffset: offset)

        // Look up entry
        if let username = usernameValue, let entry = entries[username] {
            let entryMsg = buildSearchResultEntry(messageID: messageID, entry: entry)
            write(entryMsg, to: context)
        }

        // Always send SearchResultDone
        let done = buildLDAPResult(messageID: messageID, applicationTag: 5, resultCode: 0)
        write(done, to: context)
    }

    /// Scans BER-encoded bytes for the first equalityMatch filter [3] and extracts its value.
    private func extractEqualityFilterValue(from bytes: [UInt8], startOffset: Int) -> String? {
        var i = startOffset
        while i < bytes.count {
            let tag = bytes[i]
            i += 1
            guard let len = try? parseLengthAt(bytes: bytes, offset: &i) else { break }
            let end = i + len
            // [3] CONSTRUCTED = equalityMatch: AttributeValueAssertion { attr, value }
            if tag == BERTag.contextConstructed(3) {
                let inner = Array(bytes[i ..< min(end, bytes.count)])
                var iInner = 0
                _ = try? BERDecoder.readOctetString(from: inner, offset: &iInner) // attr
                if let value = try? BERDecoder.readOctetString(from: inner, offset: &iInner) {
                    return value
                }
            }
            i = min(end, bytes.count)
        }
        return nil
    }

    // MARK: - Response Builders

    private func buildLDAPResult(messageID: Int, applicationTag: UInt8, resultCode: Int) -> [UInt8] {
        let resultCodeBytes = BEREncoder.encodeEnumerated(resultCode)
        let matchedDN = BEREncoder.encodeOctetString("")
        let diagnostic = BEREncoder.encodeOctetString("")
        let contents = resultCodeBytes + matchedDN + diagnostic
        let protocolOp = BEREncoder.encodeTagged(
            tag: BERTag.application(applicationTag),
            contents: contents
        )
        let messageContents = BEREncoder.encodeInteger(messageID) + protocolOp
        return BEREncoder.encodeSequence(messageContents)
    }

    private func buildSearchResultEntry(messageID: Int, entry: MockLDAPEntry) -> [UInt8] {
        // PartialAttribute SEQUENCE { type OCTET STRING, vals SET OF OCTET STRING }
        var attrs: [UInt8] = []

        func addAttribute(name: String, values: [String]) {
            let typeBytes = BEREncoder.encodeOctetString(name)
            let valBytes = values.flatMap { BEREncoder.encodeOctetString($0) }
            let valSet = BEREncoder.encodeTagged(tag: BERTag.set, contents: valBytes)
            let attrSeq = BEREncoder.encodeSequence(typeBytes + valSet)
            attrs += attrSeq
        }

        addAttribute(name: "cn", values: [entry.displayName ?? entry.username])
        if let email = entry.email {
            addAttribute(name: "mail", values: [email])
        }
        if !entry.groups.isEmpty {
            addAttribute(name: "memberOf", values: entry.groups)
        }

        let attrList = BEREncoder.encodeSequence(attrs)
        let objectName = BEREncoder.encodeOctetString(entry.dn)
        let contents = objectName + attrList
        let protocolOp = BEREncoder.encodeTagged(tag: BERTag.application(4), contents: contents)
        let messageContents = BEREncoder.encodeInteger(messageID) + protocolOp
        return BEREncoder.encodeSequence(messageContents)
    }

    private func write(_ bytes: [UInt8], to context: ChannelHandlerContext) {
        var buf = context.channel.allocator.buffer(capacity: bytes.count)
        buf.writeBytes(bytes)
        context.writeAndFlush(wrapOutboundOut(buf), promise: nil)
    }

    // MARK: - Length Parsing

    private func parseLengthAt(bytes: [UInt8], offset: inout Int) throws -> Int {
        guard offset < bytes.count else { throw BERDecoder.Error.truncated }
        let first = bytes[offset]
        offset += 1
        if first & 0x80 == 0 { return Int(first) }
        let numBytes = Int(first & 0x7F)
        guard numBytes > 0 && numBytes <= 4 && offset + numBytes <= bytes.count else {
            throw BERDecoder.Error.invalidLength
        }
        var length = 0
        for i in 0 ..< numBytes {
            length = (length << 8) | Int(bytes[offset + i])
        }
        offset += numBytes
        return length
    }
}

// MARK: - BERDecoder Boolean Helper

private extension BERDecoder {
    @discardableResult
    static func readBoolean(from bytes: [UInt8], offset: inout Int) throws -> Bool {
        guard offset < bytes.count, bytes[offset] == BERTag.boolean else {
            throw BERDecoder.Error.unexpectedTag(expected: BERTag.boolean, found: bytes[safe: offset] ?? 0)
        }
        offset += 1
        guard offset < bytes.count, bytes[offset] == 0x01 else {
            throw BERDecoder.Error.truncated
        }
        offset += 1
        guard offset < bytes.count else { throw BERDecoder.Error.truncated }
        let value = bytes[offset] != 0x00
        offset += 1
        return value
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - LDAPIntegrationTests

/// Integration tests that exercise ``LDAPClient`` against an in-process
/// ``MockLDAPServer``.  These tests use real TCP sockets and the full BER
/// encoding/decoding path.
final class LDAPIntegrationTests: XCTestCase {

    // MARK: - Stored Properties

    private var mockServer: MockLDAPServer!
    private var serverPort: Int = 0

    /// A service-account bind that the mock server accepts.
    private let serviceBindDN = "cn=service,dc=example,dc=com"
    private let serviceBindPassword = "svc-secret"

    // MARK: - setUp / tearDown

    override func setUp() async throws {
        try await super.setUp()
        let validBinds: [String: String] = [
            serviceBindDN: serviceBindPassword,
            "uid=alice,ou=people,dc=example,dc=com": "aliceSecret",
            "uid=bob,ou=people,dc=example,dc=com": "bobSecret"
        ]
        let entries: [String: MockLDAPEntry] = [
            "alice": MockLDAPEntry(
                dn: "uid=alice,ou=people,dc=example,dc=com",
                username: "alice",
                email: "alice@example.com",
                displayName: "Alice Example",
                groups: ["cn=admins,dc=example,dc=com"]
            ),
            "bob": MockLDAPEntry(
                dn: "uid=bob,ou=people,dc=example,dc=com",
                username: "bob",
                email: "bob@example.com",
                displayName: "Bob Example",
                groups: []
            )
        ]
        mockServer = MockLDAPServer(validBinds: validBinds, entries: entries)
        serverPort = try await mockServer.start()
    }

    override func tearDown() async throws {
        await mockServer.stop()
        mockServer = nil
        try await super.tearDown()
    }

    // MARK: - Helper

    private func makeLDAPConfig(useTLS: Bool = false) -> ServerConfiguration.LDAP {
        var schema = ServerConfiguration.LDAP.Schema()
        schema.usernameAttribute = "uid"
        schema.emailAttribute = "mail"
        schema.displayNameAttribute = "cn"
        schema.memberOfAttribute = "memberOf"
        return ServerConfiguration.LDAP(
            enabled: true,
            host: "127.0.0.1",
            port: serverPort,
            useTLS: useTLS,
            serviceBindDN: serviceBindDN,
            serviceBindPassword: serviceBindPassword,
            baseDN: "dc=example,dc=com",
            schema: schema
        )
    }

    // MARK: - Tests

    func test_ldapClient_testConnection_anonymousBind_succeeds() async throws {
        let client = LDAPClient(configuration: makeLDAPConfig())
        let reachable = try await client.testConnection()
        XCTAssertTrue(reachable, "Anonymous bind to mock server should succeed")
    }

    func test_ldapClient_bind_validServiceAccount_succeeds() async throws {
        let client = LDAPClient(configuration: makeLDAPConfig())
        // Should not throw — the service account credentials are accepted.
        try await client.bind(dn: serviceBindDN, password: serviceBindPassword)
    }

    func test_ldapClient_bind_invalidPassword_throwsInvalidCredentials() async throws {
        let client = LDAPClient(configuration: makeLDAPConfig())
        do {
            try await client.bind(dn: serviceBindDN, password: "wrong-password")
            XCTFail("Expected LDAPError.invalidCredentials")
        } catch LDAPError.invalidCredentials {
            // Expected — mock server returns result code 49 for wrong credentials.
        }
    }

    func test_ldapClient_searchUser_existingUser_returnsEntry() async throws {
        let client = LDAPClient(configuration: makeLDAPConfig())
        let entry = try await client.searchUser(username: "alice")
        XCTAssertNotNil(entry, "Expected to find alice in directory")
        XCTAssertEqual(entry?.username, "alice")
        XCTAssertEqual(entry?.email, "alice@example.com")
        XCTAssertEqual(entry?.displayName, "Alice Example")
        XCTAssertEqual(entry?.groups, ["cn=admins,dc=example,dc=com"])
    }

    func test_ldapClient_searchUser_nonExistentUser_returnsNil() async throws {
        let client = LDAPClient(configuration: makeLDAPConfig())
        let entry = try await client.searchUser(username: "nobody")
        XCTAssertNil(entry, "Non-existent user should return nil from directory search")
    }

    func test_ldapClient_authenticate_validCredentials_returnsEntry() async throws {
        let client = LDAPClient(configuration: makeLDAPConfig())
        let entry = try await client.authenticate(username: "alice", password: "aliceSecret")
        XCTAssertEqual(entry.username, "alice")
        XCTAssertEqual(entry.dn, "uid=alice,ou=people,dc=example,dc=com")
    }

    func test_ldapClient_authenticate_wrongPassword_throwsInvalidCredentials() async throws {
        let client = LDAPClient(configuration: makeLDAPConfig())
        do {
            _ = try await client.authenticate(username: "alice", password: "wrong")
            XCTFail("Expected LDAPError.invalidCredentials")
        } catch LDAPError.invalidCredentials {
            // Expected — the user bind with wrong password returns code 49.
        }
    }

    func test_ldapClient_authenticate_unknownUser_throwsUserNotFound() async throws {
        let client = LDAPClient(configuration: makeLDAPConfig())
        do {
            _ = try await client.authenticate(username: "ghost", password: "any")
            XCTFail("Expected LDAPError.userNotFound")
        } catch LDAPError.userNotFound {
            // Expected — search returns nil for unknown user.
        }
    }

    func test_ldapClient_searchUser_secondUser_returnsCorrectEntry() async throws {
        let client = LDAPClient(configuration: makeLDAPConfig())
        let entry = try await client.searchUser(username: "bob")
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.email, "bob@example.com")
        XCTAssertTrue(entry?.groups.isEmpty ?? false)
    }

    func test_ldapClient_connectionRefused_throwsConnectionFailed() async throws {
        // Point at a port with nothing listening.
        var config = makeLDAPConfig()
        config = ServerConfiguration.LDAP(
            enabled: true,
            host: "127.0.0.1",
            port: 1,   // Highly unlikely to have anything on port 1
            useTLS: false,
            serviceBindDN: serviceBindDN,
            serviceBindPassword: serviceBindPassword,
            baseDN: "dc=example,dc=com",
            schema: config.schema
        )
        let client = LDAPClient(configuration: config)
        do {
            _ = try await client.testConnection()
            XCTFail("Expected LDAPError.connectionFailed")
        } catch LDAPError.connectionFailed {
            // Expected — nothing is listening on port 1.
        }
    }
}
