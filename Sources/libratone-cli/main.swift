import Foundation
import Network

import libratone

struct LibratoneCLI {}

enum Command {
  case Listen
  case SetVolume(UInt8)
  case SetPowerState(Device.PowerStateValue)
  case SetPlayingState(Device.PlayingStateChange)
}

enum CLIError: Error {
  case InvalidCommand(String)
}

func parseCommand(s: [String]) throws -> Command {
  switch s[0] {
  case "listen":
    return .Listen
  case "set-volume":
    guard s.count == 2 else {
      throw CLIError.InvalidCommand("set-volume takes exactly one parameter")
    }
    guard let value = UInt8(s[1]) else {
      throw CLIError.InvalidCommand("set-volume parameter is not a number")
    }
    guard value <= 100 else {
      throw CLIError.InvalidCommand("set-volume parameter should be between 0 and 100")
    }

    return .SetVolume(value)
  case "set-power-state":
    guard s.count == 2 else {
      throw CLIError.InvalidCommand("set-power-state takes exactly one parameter")
    }

    var value: Device.PowerStateValue

    switch s[1] {
    case "sleeping":
      value = .Sleeping
    case "awake":
      value = .Awake
    default:
      throw CLIError.InvalidCommand("set-power-state value must be either sleeping or awake")
    }

    return .SetPowerState(value)
  case "set-playing-state":
    guard s.count == 2 else {
      throw CLIError.InvalidCommand("set-playing-state takes exactly one parameter")
    }

    var value: Device.PlayingStateChange

    switch s[1] {
    case "play":
      value = .Play
    case "pause":
      value = .Pause
    case "next":
      value = .Next
    case "previous":
      value = .Previous
    default:
      throw CLIError.InvalidCommand("set-playing-state value must be one of play, pause, next, previous")
    }

    return .SetPlayingState(value)
  default:
    throw CLIError.InvalidCommand("unknown command \(s[0])")
  }
}

extension LibratoneCLI {
  static func main() {
    let args = ProcessInfo.processInfo.arguments

    guard args.count > 1 else {
      print("Usage: \(args[0]) COMMAND [OPTIONS...]")
      exit(1)
    }

    var command: Command

    do {
      command = try parseCommand(s: Array(args[1...]))
    } catch CLIError.InvalidCommand(let s) {
      print(s)
      exit(1)
    } catch {
      print("unexpected error")
      exit(1)
    }

    do {
      let deviceManager = DeviceManager()
      deviceManager.deviceDiscoveredHandler = { device in
        print("deviceDiscoveredHandler host=\(device.host)")

        var stopCondition: ((Device.Info) -> Bool)?

        switch command {
        case .Listen:
          break
        case .SetVolume(let volume):
          stopCondition = { info in info.volume == volume }
          device.setVolume(volume: volume)
        case .SetPowerState(let state):
          stopCondition = { info in info.powerState == state }
          device.setPowerState(state: state)
        case .SetPlayingState(let state):
          stopCondition = { info in info.playingState == state }
          device.setPlayingState(state: state)
        }

        device.infoChangedHandler = { info in
          print("device.infoChangedHandler host=\(device.host) info=\(info)")

          if stopCondition?(info) ?? false {
            exit(0)
          }
        }
      }

      print("Looking for devices...")
      try deviceManager.start(queue: DispatchQueue.global())

      dispatchMain()
    } catch  {
      print("Error starting listener")
      exit(1)
    }
  }
}

LibratoneCLI.main()
