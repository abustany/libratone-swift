import Foundation

public struct SSDP {
  public enum Message: Equatable {
    case Search
    case Notify(NotifyHeaders)
  }

  public struct NotifyHeaders: Equatable {
    var data: [String: String]
  }

  enum ParseError: Error, Equatable {
    case invalidUTF8
    case invalidMessage(String)
  }


}

extension SSDP.Message {
  public static func parse(_ data: Data) throws -> SSDP.Message {
    guard let text = String(data: data, encoding: String.Encoding.utf8) else {
      throw SSDP.ParseError.invalidUTF8
    }

    let lines = text.split(separator: "\r\n")
    guard lines.count > 0 else { throw SSDP.ParseError.invalidMessage("no header line") }

    let headerTokens = lines[0].split(separator: " ", omittingEmptySubsequences: true)
    guard headerTokens.count == 3 else { throw SSDP.ParseError.invalidMessage("invalid number of tokens: \(headerTokens.count)") }
    guard headerTokens[1] == "*" else { throw SSDP.ParseError.invalidMessage("invalid path: \(headerTokens[1])") }
    guard headerTokens[2] == "HTTP/1.1" else { throw SSDP.ParseError.invalidMessage("invalid protocol: \(headerTokens[2])") }

    switch headerTokens[0] {
    case "M-SEARCH":
      return SSDP.Message.Search
    case "NOTIFY":
      return SSDP.Message.Notify(try parseHeaders(lines[1...]))
    default:
      throw SSDP.ParseError.invalidMessage("invalid method: \(headerTokens[0])")
    }
  }

  private static func parseHeaders(_ lines: ArraySlice<Substring>) throws -> SSDP.NotifyHeaders {
    var res = SSDP.NotifyHeaders()

    for line in lines {
      let tokens = line.split(separator: ":", maxSplits: 1)
      guard tokens.count == 2 else { throw SSDP.ParseError.invalidMessage("invalid number of tokens in header line: \(tokens.count)")}

      res.set(String(tokens[0]), tokens[1].trimmingCharacters(in: [" "]))
    }

    return res
  }

  public func data() -> Data {
    switch self {
    case .Search:
      return "M-SEARCH * HTTP/1.1".data(using: String.Encoding.utf8)!
    case .Notify(_):
      return "".data(using: String.Encoding.utf8)!
    }
  }
}

extension SSDP.NotifyHeaders {
  init() {
    data = [:]
  }

  fileprivate mutating func set(_ key: String, _ value: String) {
    data[key] = value
  }

  public var deviceID: String { data["DeviceID"] ?? "" }
  public var deviceName: String { data["DeviceName"] ?? "" }
}
