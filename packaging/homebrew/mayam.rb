# SPDX-License-Identifier: (see LICENSE)
#
# Homebrew formula for the Mayam PACS server.

class Mayam < Formula
  desc "Departmental PACS built in Swift — DICOM, DICOMweb, HL7 & FHIR"
  homepage "https://github.com/Raster-Lab/Mayam"
  url "https://github.com/Raster-Lab/Mayam/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "PLACEHOLDER_SHA256"
  license "SEE LICENSE"

  depends_on xcode: ["16.0", :build]
  depends_on "swift" => :build
  depends_on "postgresql@18" => :optional

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"

    bin.install ".build/release/MayamServer" => "mayam"
    etc.install "Config/mayam.yaml" => "mayam/mayam.yaml"
    (var/"lib/mayam/archive").mkpath
    (var/"log/mayam").mkpath

    # Install the launchd plist template into the formula prefix so that
    # Homebrew services can locate it.
    prefix.install "Config/com.raster-lab.mayam.plist" => "com.raster-lab.mayam.plist"
  end

  def plist_name
    "com.raster-lab.mayam"
  end

  service do
    run [opt_bin/"mayam"]
    working_dir var/"lib/mayam"
    environment_variables MAYAM_CONFIG: etc/"mayam/mayam.yaml",
                          MAYAM_STORAGE_ARCHIVE_PATH: var/"lib/mayam/archive",
                          MAYAM_LOG_LEVEL: "info"
    keep_alive crashed: true
    log_path var/"log/mayam/mayam.log"
    error_log_path var/"log/mayam/mayam-error.log"
  end

  def caveats
    <<~EOS
      Configuration file installed to:
        #{etc}/mayam/mayam.yaml

      Data directory:
        #{var}/lib/mayam/archive

      To start Mayam as a background service:
        brew services start mayam
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/mayam --version", 0)
  end
end
