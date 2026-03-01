// SPDX-License-Identifier: (see LICENSE)
// Mayam Server — Main Entry Point

import MayamCore
import Foundation

/// Mayam Server application entry point.
///
/// Loads the server configuration, initialises the logging subsystem, and starts
/// the PACS server actor.
@main
struct MayamServerApp {
    static func main() async throws {
        // Initialise logging
        MayamLogger.bootstrap()
        let logger = MayamLogger(label: "com.raster-lab.mayam.server")

        logger.info("Mayam Server starting…")

        // Load configuration
        let config: ServerConfiguration
        do {
            config = try ConfigurationLoader.load()
            logger.info("Configuration loaded successfully")
        } catch {
            logger.error("Failed to load configuration: \(error)")
            throw error
        }

        logger.info("AE Title: \(config.dicom.aeTitle)")
        logger.info("DICOM port: \(config.dicom.port)")

        // Initialise the server actor
        let server = ServerActor(configuration: config, logger: logger)
        try await server.start()
    }
}
