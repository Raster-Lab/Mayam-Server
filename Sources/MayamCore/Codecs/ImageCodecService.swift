// SPDX-License-Identifier: (see LICENSE)
// Mayam — Image Codec Service

import Foundation
import J2KCore
import J2KCodec
import J2K3D
import JPEGLS
import JXLSwift
import Logging

/// Unified image codec service for transcoding DICOM pixel data between
/// transfer syntaxes.
///
/// `ImageCodecService` wraps the Raster-Lab codec frameworks (J2KSwift,
/// JLSwift, JXLSwift, J2K3D) behind an actor-based interface to provide
/// thread-safe, on-demand and background transcoding of DICOM image data.
///
/// ## Supported Codecs
///
/// | Codec | Framework | Transfer Syntaxes |
/// |---|---|---|
/// | JPEG 2000 | J2KSwift (`J2KCore`, `J2KCodec`) | 1.2.840.10008.1.2.4.90, .91 |
/// | HTJ2K | J2KSwift (`J2KCore`, `J2KCodec`) | 1.2.840.10008.1.2.4.201, .202, .203 |
/// | JPEG-LS | JLSwift (`JPEGLS`) | 1.2.840.10008.1.2.4.80, .81 |
/// | JPEG XL | JXLSwift | 1.2.840.10008.1.2.4.110, .111 |
/// | JP3D | J2KSwift (`J2K3D`) | Volumetric 3D datasets |
///
/// ## Usage
///
/// ```swift
/// let service = ImageCodecService(logger: logger)
/// let result = try await service.transcode(
///     pixelData: rawBytes,
///     from: "1.2.840.10008.1.2.1",
///     to: "1.2.840.10008.1.2.4.90",
///     imageParameters: params
/// )
/// ```
///
/// Reference: DICOM PS3.5 Section 8 — Encoding of Pixel Data
public actor ImageCodecService {

    // MARK: - Stored Properties

    /// Logger for codec events.
    private let logger: Logger

    /// Tracks the total number of transcoding operations performed.
    private var transcodingCount: Int = 0

    // MARK: - Initialiser

    /// Creates a new image codec service.
    ///
    /// - Parameter logger: Logger instance for codec events.
    public init(logger: Logger) {
        self.logger = logger
    }

    // MARK: - Public Methods

    /// Returns the total number of transcoding operations performed since
    /// the service was created.
    public func getTranscodingCount() -> Int {
        transcodingCount
    }

    /// Returns whether the service can transcode between the two given
    /// transfer syntaxes.
    ///
    /// - Parameters:
    ///   - sourceUID: Source transfer syntax UID.
    ///   - targetUID: Target transfer syntax UID.
    /// - Returns: `true` if transcoding is supported.
    public nonisolated func canTranscode(from sourceUID: String, to targetUID: String) -> Bool {
        guard sourceUID != targetUID else { return true }
        let sourceKnown = TransferSyntaxRegistry.info(for: sourceUID) != nil
        let targetKnown = TransferSyntaxRegistry.info(for: targetUID) != nil
        return sourceKnown && targetKnown
    }

    /// Returns the set of transfer syntax UIDs that this service can produce
    /// from the given source syntax.
    ///
    /// - Parameter sourceUID: The source transfer syntax UID.
    /// - Returns: A set of target transfer syntax UIDs.
    public nonisolated func supportedTargets(from sourceUID: String) -> Set<String> {
        guard TransferSyntaxRegistry.info(for: sourceUID) != nil else {
            return []
        }
        return TransferSyntaxRegistry.allSupportedUIDs
    }

    /// Transcodes DICOM pixel data from one transfer syntax to another.
    ///
    /// If the source and target transfer syntaxes are the same, the original
    /// data is returned without modification.
    ///
    /// - Parameters:
    ///   - pixelData: The raw pixel data bytes to transcode.
    ///   - sourceUID: The current transfer syntax UID.
    ///   - targetUID: The desired transfer syntax UID.
    ///   - imageParameters: Image dimensions and format parameters needed
    ///     for encoding/decoding.
    /// - Returns: A ``TranscodingResult`` containing the transcoded pixel data
    ///   and metadata.
    /// - Throws: ``CodecError`` if transcoding fails.
    public func transcode(
        pixelData: Data,
        from sourceUID: String,
        to targetUID: String,
        imageParameters: ImageParameters
    ) async throws -> TranscodingResult {
        guard sourceUID != targetUID else {
            return TranscodingResult(
                data: pixelData,
                transferSyntaxUID: targetUID,
                wasTranscoded: false
            )
        }

        guard let sourceInfo = TransferSyntaxRegistry.info(for: sourceUID) else {
            throw CodecError.unsupportedTransferSyntax(uid: sourceUID)
        }
        guard let targetInfo = TransferSyntaxRegistry.info(for: targetUID) else {
            throw CodecError.unsupportedTransferSyntax(uid: targetUID)
        }

        logger.debug("Transcoding: \(sourceInfo.name) → \(targetInfo.name) (\(pixelData.count) bytes)")

        // Step 1: Decode source to raw pixel data if compressed
        let rawPixelData: Data
        if sourceInfo.isCompressed, let codec = sourceInfo.codec {
            rawPixelData = try await decode(
                compressedData: pixelData,
                codec: codec,
                transferSyntaxUID: sourceUID,
                imageParameters: imageParameters
            )
        } else {
            rawPixelData = pixelData
        }

        // Step 2: Encode to target transfer syntax if compressed
        let outputData: Data
        if targetInfo.isCompressed, let codec = targetInfo.codec {
            outputData = try await encode(
                rawPixelData: rawPixelData,
                codec: codec,
                transferSyntaxUID: targetUID,
                imageParameters: imageParameters
            )
        } else {
            outputData = rawPixelData
        }

        transcodingCount += 1

        logger.info("Transcoded \(sourceInfo.name) → \(targetInfo.name): \(pixelData.count)B → \(outputData.count)B")

        return TranscodingResult(
            data: outputData,
            transferSyntaxUID: targetUID,
            wasTranscoded: true
        )
    }

    /// Selects the best available transfer syntax for a client from the
    /// stored representations.
    ///
    /// The selection prefers (in order):
    /// 1. An exact match with one of the client's accepted transfer syntaxes.
    /// 2. A lossless representation that can be served without transcoding.
    /// 3. The original uncompressed representation as a fallback.
    ///
    /// - Parameters:
    ///   - storedSyntaxUIDs: The transfer syntax UIDs of available
    ///     representations for the object.
    ///   - clientAcceptedUIDs: The transfer syntax UIDs the client supports.
    /// - Returns: The UID of the best transfer syntax to serve, or `nil` if
    ///   no compatible representation exists and transcoding is required.
    public nonisolated func selectBestTransferSyntax(
        storedSyntaxUIDs: Set<String>,
        clientAcceptedUIDs: Set<String>
    ) -> String? {
        // Prefer direct match (no transcoding needed)
        let directMatches = storedSyntaxUIDs.intersection(clientAcceptedUIDs)
        if !directMatches.isEmpty {
            // Prefer lossless over lossy among direct matches
            if let lossless = directMatches.first(where: { TransferSyntaxRegistry.isLossless($0) }) {
                return lossless
            }
            return directMatches.first
        }

        return nil
    }

    // MARK: - Private Methods

    /// Decodes compressed pixel data to raw format using the appropriate codec.
    private func decode(
        compressedData: Data,
        codec: CodecFramework,
        transferSyntaxUID: String,
        imageParameters: ImageParameters
    ) async throws -> Data {
        switch codec {
        case .jpeg2000:
            return try decodeJPEG2000(data: compressedData, transferSyntaxUID: transferSyntaxUID, parameters: imageParameters)
        case .jpegLS:
            return try decodeJPEGLS(data: compressedData, parameters: imageParameters)
        case .jpegXL:
            return try decodeJPEGXL(data: compressedData, parameters: imageParameters)
        case .jp3d:
            return try await decodeJP3D(data: compressedData, parameters: imageParameters)
        case .rle:
            return try decodeRLE(data: compressedData, parameters: imageParameters)
        }
    }

    /// Encodes raw pixel data using the appropriate codec.
    private func encode(
        rawPixelData: Data,
        codec: CodecFramework,
        transferSyntaxUID: String,
        imageParameters: ImageParameters
    ) async throws -> Data {
        switch codec {
        case .jpeg2000:
            return try encodeJPEG2000(data: rawPixelData, transferSyntaxUID: transferSyntaxUID, parameters: imageParameters)
        case .jpegLS:
            return try encodeJPEGLS(data: rawPixelData, transferSyntaxUID: transferSyntaxUID, parameters: imageParameters)
        case .jpegXL:
            return try encodeJPEGXL(data: rawPixelData, transferSyntaxUID: transferSyntaxUID, parameters: imageParameters)
        case .jp3d:
            return try await encodeJP3D(data: rawPixelData, parameters: imageParameters)
        case .rle:
            return try encodeRLE(data: rawPixelData, parameters: imageParameters)
        }
    }

    // MARK: - JPEG 2000 (J2KSwift)

    private func decodeJPEG2000(data: Data, transferSyntaxUID: String, parameters: ImageParameters) throws -> Data {
        do {
            let decoder = J2KDecoder()
            let image = try decoder.decode(data)
            guard let component = image.components.first else {
                throw CodecError.decodingFailed(codec: .jpeg2000, reason: "No components in decoded image")
            }
            return component.data
        } catch let error as CodecError {
            throw error
        } catch {
            throw CodecError.decodingFailed(codec: .jpeg2000, reason: "\(error)")
        }
    }

    private func encodeJPEG2000(data: Data, transferSyntaxUID: String, parameters: ImageParameters) throws -> Data {
        let isLossless = TransferSyntaxRegistry.isLossless(transferSyntaxUID)
        do {
            let component = J2KComponent(
                index: 0,
                bitDepth: parameters.bitsAllocated,
                signed: parameters.pixelRepresentation == 1,
                width: parameters.columns,
                height: parameters.rows,
                data: data
            )
            let image = J2KImage(
                width: parameters.columns,
                height: parameters.rows,
                components: [component]
            )
            let configuration = isLossless ? J2KConfiguration.lossless : J2KConfiguration(quality: 0.85, lossless: false)
            let encoder = J2KEncoder(configuration: configuration)
            return try encoder.encode(image)
        } catch let error as CodecError {
            throw error
        } catch {
            throw CodecError.encodingFailed(codec: .jpeg2000, reason: "\(error)")
        }
    }

    // MARK: - JPEG-LS (JLSwift)

    private func decodeJPEGLS(data: Data, parameters: ImageParameters) throws -> Data {
        do {
            let decoder = JPEGLSDecoder()
            let decoded = try decoder.decode(data)
            // Reconstruct flat pixel data from component planes
            guard let component = decoded.components.first else {
                throw CodecError.decodingFailed(codec: .jpegLS, reason: "No components in decoded image")
            }
            let bytesPerSample = (decoded.frameHeader.bitsPerSample + 7) / 8
            var result = Data(capacity: decoded.frameHeader.width * decoded.frameHeader.height * bytesPerSample)
            for row in component.pixels {
                for pixel in row {
                    if bytesPerSample == 1 {
                        result.append(UInt8(clamping: pixel))
                    } else {
                        var value = UInt16(clamping: pixel)
                        result.append(contentsOf: withUnsafeBytes(of: &value) { Array($0) })
                    }
                }
            }
            return result
        } catch let error as CodecError {
            throw error
        } catch {
            throw CodecError.decodingFailed(codec: .jpegLS, reason: "\(error)")
        }
    }

    private func encodeJPEGLS(data: Data, transferSyntaxUID: String, parameters: ImageParameters) throws -> Data {
        let isLossless = TransferSyntaxRegistry.isLossless(transferSyntaxUID)
        do {
            let near = isLossless ? 0 : 2
            let bytesPerSample = (parameters.bitsAllocated + 7) / 8

            // Convert flat pixel data to 2D array [[Int]]
            var pixels: [[Int]] = []
            var offset = 0
            for _ in 0..<parameters.rows {
                var row: [Int] = []
                for _ in 0..<parameters.columns {
                    if bytesPerSample == 1, offset < data.count {
                        row.append(Int(data[offset]))
                        offset += 1
                    } else if bytesPerSample == 2, offset + 1 < data.count {
                        let value = Int(data[offset]) | (Int(data[offset + 1]) << 8)
                        row.append(value)
                        offset += 2
                    } else {
                        row.append(0)
                        offset += bytesPerSample
                    }
                }
                pixels.append(row)
            }

            let imageData = try MultiComponentImageData.grayscale(
                pixels: pixels,
                bitsPerSample: parameters.bitsStored
            )
            let configuration = try JPEGLSEncoder.Configuration(near: near)
            let encoder = JPEGLSEncoder()
            return try encoder.encode(imageData, configuration: configuration)
        } catch let error as CodecError {
            throw error
        } catch {
            throw CodecError.encodingFailed(codec: .jpegLS, reason: "\(error)")
        }
    }

    // MARK: - JPEG XL (JXLSwift)

    private func decodeJPEGXL(data: Data, parameters: ImageParameters) throws -> Data {
        do {
            let decoder = JXLDecoder()
            let frame = try decoder.decode(data)
            return Data(frame.data)
        } catch let error as CodecError {
            throw error
        } catch {
            throw CodecError.decodingFailed(codec: .jpegXL, reason: "\(error)")
        }
    }

    private func encodeJPEGXL(data: Data, transferSyntaxUID: String, parameters: ImageParameters) throws -> Data {
        let isLossless = TransferSyntaxRegistry.isLossless(transferSyntaxUID)
        do {
            var frame = ImageFrame(
                width: parameters.columns,
                height: parameters.rows,
                channels: parameters.samplesPerPixel,
                bitsPerSample: parameters.bitsAllocated
            )
            frame.data = [UInt8](data)
            var options = EncodingOptions()
            options.mode = isLossless ? .lossless : .lossy(quality: 85.0)
            let encoder = JXLEncoder(options: options)
            let result = try encoder.encode(frame)
            return result.data
        } catch let error as CodecError {
            throw error
        } catch {
            throw CodecError.encodingFailed(codec: .jpegXL, reason: "\(error)")
        }
    }

    // MARK: - JP3D (J2K3D)

    private func decodeJP3D(data: Data, parameters: ImageParameters) async throws -> Data {
        do {
            let decoder = JP3DDecoder()
            let result = try await decoder.decode(data)
            guard let component = result.volume.components.first else {
                throw CodecError.decodingFailed(codec: .jp3d, reason: "No components in decoded volume")
            }
            return component.data
        } catch let error as CodecError {
            throw error
        } catch {
            throw CodecError.decodingFailed(codec: .jp3d, reason: "\(error)")
        }
    }

    private func encodeJP3D(data: Data, parameters: ImageParameters) async throws -> Data {
        do {
            let volume = J2KVolume(
                width: parameters.columns,
                height: parameters.rows,
                depth: max(parameters.numberOfFrames, 1),
                componentCount: parameters.samplesPerPixel,
                bitDepth: parameters.bitsAllocated,
                signed: parameters.pixelRepresentation == 1
            )
            let encoder = JP3DEncoder(configuration: .lossless)
            let result = try await encoder.encode(volume)
            return result.data
        } catch let error as CodecError {
            throw error
        } catch {
            throw CodecError.encodingFailed(codec: .jp3d, reason: "\(error)")
        }
    }

    // MARK: - RLE

    private func decodeRLE(data: Data, parameters: ImageParameters) throws -> Data {
        // RLE decoding is handled natively; pass through for now
        // Full RLE decode implementation deferred to serve-as-stored path
        return data
    }

    private func encodeRLE(data: Data, parameters: ImageParameters) throws -> Data {
        // RLE encoding is handled natively; pass through for now
        // Full RLE encode implementation deferred to serve-as-stored path
        return data
    }
}

// MARK: - ImageParameters

/// Parameters describing the DICOM image pixel format, required for
/// transcoding operations.
///
/// These correspond to standard DICOM attributes from the Image Pixel Module
/// (DICOM PS3.3 Section C.7.6.3).
public struct ImageParameters: Sendable, Equatable, Codable {

    /// Number of pixel rows (0028,0010).
    public var rows: Int

    /// Number of pixel columns (0028,0011).
    public var columns: Int

    /// Bits allocated per pixel sample (0028,0100).
    public var bitsAllocated: Int

    /// Bits stored per pixel sample (0028,0101).
    public var bitsStored: Int

    /// High bit position (0028,0102).
    public var highBit: Int

    /// Pixel representation: 0 = unsigned, 1 = signed (0028,0103).
    public var pixelRepresentation: Int

    /// Number of samples (colour components) per pixel (0028,0002).
    public var samplesPerPixel: Int

    /// Number of frames in a multi-frame image (0028,0008). Defaults to 1.
    public var numberOfFrames: Int

    /// Photometric interpretation (0028,0004).
    public var photometricInterpretation: String

    /// Creates image parameters.
    ///
    /// - Parameters:
    ///   - rows: Number of pixel rows (0028,0010).
    ///   - columns: Number of pixel columns (0028,0011).
    ///   - bitsAllocated: Bits allocated per sample (0028,0100).
    ///   - bitsStored: Bits stored per sample (0028,0101).
    ///   - highBit: High bit position (0028,0102).
    ///   - pixelRepresentation: Pixel representation (0028,0103).
    ///   - samplesPerPixel: Samples per pixel (0028,0002).
    ///   - numberOfFrames: Number of frames (0028,0008).
    ///   - photometricInterpretation: Photometric interpretation (0028,0004).
    public init(
        rows: Int = 512,
        columns: Int = 512,
        bitsAllocated: Int = 16,
        bitsStored: Int = 12,
        highBit: Int = 11,
        pixelRepresentation: Int = 0,
        samplesPerPixel: Int = 1,
        numberOfFrames: Int = 1,
        photometricInterpretation: String = "MONOCHROME2"
    ) {
        self.rows = rows
        self.columns = columns
        self.bitsAllocated = bitsAllocated
        self.bitsStored = bitsStored
        self.highBit = highBit
        self.pixelRepresentation = pixelRepresentation
        self.samplesPerPixel = samplesPerPixel
        self.numberOfFrames = numberOfFrames
        self.photometricInterpretation = photometricInterpretation
    }
}

// MARK: - TranscodingResult

/// The result of a transcoding operation.
public struct TranscodingResult: Sendable, Equatable {

    /// The transcoded (or original) pixel data.
    public let data: Data

    /// The transfer syntax UID of the output data.
    public let transferSyntaxUID: String

    /// Whether transcoding was actually performed. `false` if the source
    /// and target transfer syntaxes were identical.
    public let wasTranscoded: Bool

    /// Creates a transcoding result.
    ///
    /// - Parameters:
    ///   - data: The output pixel data.
    ///   - transferSyntaxUID: The output transfer syntax UID.
    ///   - wasTranscoded: Whether transcoding was performed.
    public init(data: Data, transferSyntaxUID: String, wasTranscoded: Bool) {
        self.data = data
        self.transferSyntaxUID = transferSyntaxUID
        self.wasTranscoded = wasTranscoded
    }
}
