// SPDX-License-Identifier: (see LICENSE)
// Mayam Server — Server Actor

import Logging

/// The top-level server actor that coordinates all PACS subsystems.
///
/// `ServerActor` owns the lifecycle of the DICOM listener, manages the pool of
/// ``AssociationActor`` instances, and coordinates the ``StorageActor`` for
/// persistent object management.
///
/// ## Architecture
///
/// ```
/// ServerActor
/// ├── AssociationActor (one per active DICOM association)
/// └── StorageActor (singleton, manages archive I/O)
/// ```
///
/// All mutable server state is isolated within this actor, eliminating data
/// races under Swift strict concurrency.
public actor ServerActor {

    // MARK: - Stored Properties

    /// The server configuration.
    public let configuration: ServerConfiguration

    /// Logger for server-level events.
    private let logger: MayamLogger

    /// The storage actor for managing DICOM object persistence.
    private let storageActor: StorageActor

    /// Tracks whether the server is currently running.
    private var isRunning: Bool = false

    /// The number of active DICOM associations.
    private var activeAssociationCount: Int = 0

    // MARK: - Initialiser

    /// Creates a new server actor with the given configuration.
    ///
    /// - Parameters:
    ///   - configuration: The server configuration.
    ///   - logger: The logger instance for server events.
    public init(configuration: ServerConfiguration, logger: MayamLogger) {
        self.configuration = configuration
        self.logger = logger
        self.storageActor = StorageActor(
            archivePath: configuration.storage.archivePath,
            checksumEnabled: configuration.storage.checksumEnabled,
            logger: MayamLogger(label: "com.raster-lab.mayam.storage")
        )
    }

    // MARK: - Public Methods

    /// Starts the PACS server.
    ///
    /// This method initialises the DICOM TCP listener and begins accepting
    /// inbound associations.  It suspends until the server is shut down.
    ///
    /// - Throws: If the server cannot bind to the configured port.
    public func start() async throws {
        guard !isRunning else {
            logger.warning("Server is already running")
            return
        }

        isRunning = true
        logger.info("Server started on port \(configuration.dicom.port) with AE Title '\(configuration.dicom.aeTitle)'")

        // Placeholder: In Milestone 2, this will start the Swift NIO TCP
        // listener and begin accepting DICOM associations.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            // Keep the server alive until explicitly stopped.
            // The actual NIO event loop will replace this in Milestone 2.
            _ = continuation
        }
    }

    /// Gracefully shuts down the server.
    ///
    /// Drains in-flight associations before closing the listener.
    public func shutdown() async {
        logger.info("Server shutting down…")
        isRunning = false
        logger.info("Server stopped")
    }

    /// Returns the current number of active DICOM associations.
    public func getActiveAssociationCount() -> Int {
        activeAssociationCount
    }

    /// Returns whether the server is currently running.
    public func getIsRunning() -> Bool {
        isRunning
    }
}
