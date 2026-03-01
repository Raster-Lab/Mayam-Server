// SPDX-License-Identifier: (see LICENSE)
// Mayam Server — MayamWeb Tests

import XCTest
@testable import MayamWeb

final class MayamWebTests: XCTestCase {

    func test_mayamWeb_version_isSet() {
        XCTAssertEqual(MayamWeb.version, "0.1.0")
    }
}
