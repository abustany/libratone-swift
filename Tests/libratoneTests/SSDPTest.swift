import XCTest

@testable import libratone

class SSDPTest: XCTestCase {
  private func d(_ s: String) -> Data {
    return s.data(using: String.Encoding.utf8)!
  }

  func testParseUnknownMethod() throws {
    XCTAssertThrowsError(try SSDP.Message.parse(d("WAT * HTTP/1.1\r\n"))) { error in
      XCTAssertEqual(error as! SSDP.ParseError, SSDP.ParseError.invalidMessage("invalid method: WAT"))
    }
  }

  func testParseSearch() throws {
    XCTAssertEqual(try SSDP.Message.parse(d("M-SEARCH * HTTP/1.1\r\n")), SSDP.Message.Search)
  }

  func testParseNotify() throws {
    XCTAssertEqual(
      try SSDP.Message.parse(d("NOTIFY * HTTP/1.1\r\nFoo: Bar\r\nHello: World:Yep\r\n")),
      SSDP.Message.Notify(SSDP.NotifyHeaders(data: [
        "Foo": "Bar",
        "Hello": "World:Yep"
      ]))
    )
  }
}
