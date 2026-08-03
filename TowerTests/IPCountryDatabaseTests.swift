import XCTest
@testable import Tower

final class IPCountryDatabaseTests: XCTestCase {
    func testLooksUpIPv4CountryWithBinarySearch() {
        var data = Data()
        appendIPv4Record(start: 0x01000000, end: 0x010000FF, code: "AU", to: &data)
        appendIPv4Record(start: 0x08080800, end: 0x080808FF, code: "US", to: &data)
        let database = IPCountryDatabase(ipv4Data: data, ipv6Data: Data())

        XCTAssertEqual(database.countryCode(forIPAddress: "1.0.0.8"), "AU")
        XCTAssertEqual(database.countryCode(forIPAddress: "8.8.8.8"), "US")
        XCTAssertNil(database.countryCode(forIPAddress: "9.9.9.9"))
    }

    func testLooksUpIPv6CountryWithBinarySearch() {
        let start: [UInt8] = [0x20, 0x01, 0x0D, 0xB8] + Array(repeating: 0, count: 12)
        let end: [UInt8] = [0x20, 0x01, 0x0D, 0xB8] + Array(repeating: 0xFF, count: 12)
        let database = IPCountryDatabase(
            ipv4Data: Data(),
            ipv6Data: Data(start + end + Array("JP".utf8))
        )

        XCTAssertEqual(database.countryCode(forIPAddress: "2001:db8::42"), "JP")
        XCTAssertNil(database.countryCode(forIPAddress: "2001:4860::1"))
    }

    func testBundledDatabaseIsAvailableToTheApp() {
        let countryCode = IPCountryDatabase().countryCode(forIPAddress: "1.1.1.1")

        XCTAssertEqual(countryCode?.count, 2)
    }

    func testLookupServiceUsesNumericServerAddressWithoutNetworkAPI() async {
        var data = Data()
        appendIPv4Record(start: 0x08080800, end: 0x080808FF, code: "US", to: &data)
        let service = IPCountryLookupService(
            database: IPCountryDatabase(ipv4Data: data, ipv6Data: Data())
        )

        let countryCode = await service.countryCode(forHost: "8.8.8.8")

        XCTAssertEqual(countryCode, "US")
    }

    private func appendIPv4Record(start: UInt32, end: UInt32, code: String, to data: inout Data) {
        for value in [start, end] {
            data.append(UInt8((value >> 24) & 0xFF))
            data.append(UInt8((value >> 16) & 0xFF))
            data.append(UInt8((value >> 8) & 0xFF))
            data.append(UInt8(value & 0xFF))
        }
        data.append(contentsOf: code.utf8)
    }
}
