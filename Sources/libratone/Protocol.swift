import Foundation

public struct Proto {
  public struct Packet {
    let commandType: CommandType
    let command: UInt16
    let commandData: Data?
  }

  public enum ParseError: Error, Equatable {
    case tooShort
    case inconsistentLength
    case invalidCommandType
  }

  public enum CommandType: UInt8 {
    case fetch = 1
    case set = 2
  }
}

extension Proto.Packet {
  init(_ data: Data) throws {
    let headerLen = 10
    guard data.count >= headerLen else { throw Proto.ParseError.tooShort }

    let dataLen = UInt16(data[8]) << 8 | UInt16(data[9])
    guard headerLen+Int(dataLen) == data.count else { throw Proto.ParseError.inconsistentLength }

    if let t = Proto.CommandType(rawValue: data[2]) {
      commandType = t
    } else {
      throw Proto.ParseError.invalidCommandType
    }

    command = UInt16(data[3]) << 8 | UInt16(data[4])
    commandData = dataLen > 0 ? data.subdata(in: headerLen..<data.count) : nil
  }

  func data() -> Data {
    let dataLen = (commandData?.count ?? 0)
    var res = Data(count: 10+dataLen)
    res[0] = 0xaa
    res[1] = 0xaa
    res[2] = commandType.rawValue
    res[3] = UInt8((command & 0xff00) >> 8)
    res[4] = UInt8(command & 0xff)
    res[5] = 0x00
    res[6] = 0x12
    res[7] = 0x34
    res[8] = UInt8((dataLen & 0xff00) >> 8)
    res[9] = UInt8(dataLen & 0xff)

    if (dataLen > 0) {
      res[10...] = commandData!
    }

    return res
  }
}
