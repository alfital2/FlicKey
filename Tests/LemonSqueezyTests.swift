import XCTest

// Parses against the REAL responses captured from the Lemon Squeezy license API
// for the FlicKey store (store 400531).
final class LemonSqueezyTests: XCTestCase {

    private let validateJSON = """
    {"valid":true,"error":null,
     "license_key":{"id":1419582,"status":"inactive","key":"5E9D82AE","activation_limit":3,"activation_usage":0,"expires_at":null,"test_mode":true},
     "instance":null,
     "meta":{"store_id":400531,"order_id":8630956,"variant_name":"Default","product_id":1124523,"product_name":"FlicKey License","customer_name":"flickey","customer_email":"flickey.support@gmail.com"}}
    """.data(using: .utf8)!

    private let activateJSON = """
    {"activated":true,"error":null,
     "license_key":{"id":1419582,"status":"active","key":"5E9D82AE","activation_limit":3,"activation_usage":1,"expires_at":null,"test_mode":true},
     "instance":{"id":"1782e0c1-d7ee-4119-b6e8-75dc9299a5e5","name":"Tal-test-Mac","created_at":"2026-06-07T20:38:20.000000Z"},
     "meta":{"store_id":400531,"order_id":8630956,"variant_name":"Default","product_id":1124523,"product_name":"FlicKey License","customer_name":"flickey","customer_email":"flickey.support@gmail.com"}}
    """.data(using: .utf8)!

    func testParseValidate() throws {
        let lic = try LemonSqueezy.parse(validateJSON, kind: .validate)
        XCTAssertTrue(lic.valid)
        XCTAssertEqual(lic.storeID, 400531)
        XCTAssertEqual(lic.productName, "FlicKey License")
        XCTAssertEqual(lic.customerEmail, "flickey.support@gmail.com")
        XCTAssertNil(lic.instanceID)
    }

    func testParseActivate() throws {
        let lic = try LemonSqueezy.parse(activateJSON, kind: .activate)
        XCTAssertTrue(lic.valid)
        XCTAssertEqual(lic.instanceID, "1782e0c1-d7ee-4119-b6e8-75dc9299a5e5")
    }

    func testWrongStoreRejected() {
        let other = String(data: activateJSON, encoding: .utf8)!
            .replacingOccurrences(of: "\"store_id\":400531", with: "\"store_id\":999999")
            .data(using: .utf8)!
        XCTAssertThrowsError(try LemonSqueezy.parse(other, kind: .activate)) { error in
            XCTAssertEqual(error as? LemonSqueezy.LSError, .wrongStore)
        }
    }

    func testInvalidKeyReturnsMessageNotThrow() throws {
        let json = """
        {"valid":false,"error":"license_key not found.","license_key":null,"instance":null,"meta":null}
        """.data(using: .utf8)!
        let lic = try LemonSqueezy.parse(json, kind: .validate)
        XCTAssertFalse(lic.valid)
        XCTAssertEqual(lic.errorMessage, "license_key not found.")
    }
}
