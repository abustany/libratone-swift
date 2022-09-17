import Foundation
import Network

public class Device {
  public struct Info: Equatable {
    public var name: String?
    public var volume: UInt8? // 0-100
    public var powerState: PowerStateValue?
    public var playingState: PlayingStateChange?
    public var currentTrack: CurrentTrackData?
    public var favorites: [Favorite]?

    public init() {}
  }

  public enum PowerStateValue {
    case Sleeping
    case Awake
  }

  public enum PlayingStateChange {
    case Play
    case Stop
    case Pause
    case Next
    case Previous
    case Toggle
    case Mute
    case Unmute
  }

  public struct CurrentTrackData : Equatable {
    public var isFromChannel: Bool?
    public var playAlbum: String?
    public var playAlbumURI: String?
    public var playArtist: String?
    public var playAttribution: String?
    public var playIdentity: String?
    public var playObject: String?
    public var playPic: String?
    public var playPresetAvailable: Int?
    public var playSubtitle: String?
    public var playTitle: String?
    public var playType: String?
    public var playUsername: String?
    public var playToken: String?

    public init() {}
  }

  public struct Favorite : Equatable {
    public enum ChannelType: String {
      case VTuner = "vtuner"
      case XMLY = "xmly"
      case DoubanFM = "doubanfm"
      case Spotify = "spotify"
      case Kaishu = "kaishu"
      case Deezer = "deezer"
      case Tidal = "tidal"
      case Napster = "napster"
    }

    public var isPlaying: Bool?
    public var channelID: String?
    public var channelType: ChannelType?
    public var channelName: String?
    public var channelIdentity: String?
    public var stationURL: String?
    public var pictureURL: String?
    public var username: String?
    public var password: String?
    public var playToken: String?

    public init() {}
  }

  public let host: NWEndpoint.Host
  let commandConn: NWConnection
  let ackConn: NWConnection
  var info: Info? {
    didSet {
      guard info != nil else { return }
      self.infoChangedHandler?(info!)
    }
  }
  public var infoChangedHandler: ((Info) -> Void)?

  init(queue: DispatchQueue, host: NWEndpoint.Host) {
    self.host = host
    self.commandConn = NWConnection(host: host, port: 7777, using: NWParameters.udp)
    self.ackConn = NWConnection(host: host, port: 3334, using: NWParameters.udp)

    self.commandConn.stateUpdateHandler = { state in
      switch state {
      case .ready:
        logger.debug("Connected to \(host), fetching info")
        self.fetchInfo()
      case .failed(let err):
        logger.error("Failed to connect to \(host) for commands: \(err)")
      default:
        break
      }
    }

    self.ackConn.stateUpdateHandler = { state in
      switch state {
      case .failed(let err):
        logger.error("Failed to connect to \(host) for ack: \(err)")
      default:
        break
      }
    }

    self.commandConn.start(queue: queue)
    self.ackConn.start(queue: queue)
  }

  func updateInfo(_ f: @escaping (inout Info) -> Void) {
    DispatchQueue.main.async {
      var updatedInfo = self.info ?? Info()
      f(&updatedInfo)
      self.info = updatedInfo
    }
  }

  func handleReply(packet: Proto.Packet) {
    logger.debug("Got reply \(packet)")

    guard let command = Device.Commands.first(where: {type(of: $0).fetch == packet.command}) as? UpdateInfoProperty else {
      logger.debug("Ignoring reply to unknown command \(packet.command)")
      return
    }

    guard packet.commandData != nil else {
      // replies to a set don't have data, you get a notify instead
      return
    }

    self.updateInfo { info in
      type(of: command).updateInfo(d: packet.commandData!, info: &info)
    }
  }

  func handleNotify(packet: Proto.Packet) {
    logger.debug("Got notify \(packet)")
    Device.sendPacket(conn: self.ackConn, packet: Proto.Packet(commandType: .set, command: packet.command, commandData: nil))

    guard let command = Device.Commands.first(where: { cmd in
      guard let notifyCmd = cmd as? NotifyProperty else { return false }
      return type(of: notifyCmd).notify == packet.command
    }) as? UpdateInfoProperty else {
      logger.debug("Ignoring notify from unknown command \(packet.command)")
      return
    }

    guard packet.commandData != nil else {
      logger.error("No data for notify from \(type(of: command).name)")
      return
    }

    self.updateInfo { info in
      type(of: command).updateInfo(d: packet.commandData!, info: &info)
    }
  }

  private func fetchInfo() {
    fetch(Device.Name)
    fetch(Device.Volume)
    fetch(Device.PowerState)
    fetch(Device.PlayingState)
    fetch(Device.CurrentTrack)
    fetch(Device.Favorites)
  }

  public func setVolume(volume: UInt8) {
    set(Device.Volume, value: volume)
  }

  public func setPowerState(state: PowerStateValue) {
    set(Device.PowerState, value: state)
  }

  public func setPlayingState(state: PlayingStateChange) {
    set(Device.PlayingState, value: state)
  }

  public func setCurrentTrack(track: CurrentTrackData) {
    set(Device.CurrentTrack, value: track)
  }

  static let Name = NameProperty()
  static let Volume = VolumeProperty()
  static let PowerState = PowerStateProperty()
  static let PlayingState = PlayingStateProperty()
  static let CurrentTrack = CurrentTrackProperty()
  static let Favorites = FavoritesProperty()
  static let Commands: [BaseProperty] = [Name, Volume, PowerState, PlayingState, CurrentTrack, Favorites]

  private func fetch<PropType: BaseProperty>(_ prop: PropType) {
    Device.sendPacket(conn: self.commandConn, packet: Proto.Packet(commandType: .fetch, command: PropType.fetch, commandData: nil))
  }

  private func set<PropType: SettableProperty>(_ prop: PropType, value: PropType.DataType) {
    Device.sendPacket(conn: self.commandConn, packet: Proto.Packet(commandType: .set, command: PropType.set, commandData: PropType.marshalData(d: value)))
  }

  private static func sendPacket(conn: NWConnection, packet: Proto.Packet) {
    conn.send(
      content: packet.data(),
      completion: NWConnection.SendCompletion.contentProcessed({err in
        if err != nil {
          logger.error("Error sending packet to \(conn.endpoint): \(err!)")
        }
      })
    )
  }
}

protocol BaseProperty {
  static var name: String { get }
  static var fetch: UInt16 { get }
}

protocol NotifyProperty: BaseProperty {
  static var notify: UInt16 { get }
}

protocol UpdateInfoProperty: BaseProperty {
  static func updateInfo(d: Data, info: inout Device.Info)
}

protocol SettableProperty: BaseProperty {
  static var set: UInt16 { get }

  associatedtype DataType
  static func marshalData(d: DataType) -> Data
}

func parseString(_ d: Data) -> String? {
  String(data: d, encoding: String.Encoding.utf8)
}

struct NameProperty: UpdateInfoProperty {
  static let name = "Name"
  static let fetch: UInt16 = 90
  static let set: UInt16 = 90

  static func updateInfo(d: Data, info: inout Device.Info) {
    if let name = parseString(d) {
      info.name = name
    }
  }
}

struct VolumeProperty: NotifyProperty, UpdateInfoProperty, SettableProperty {
  static let name = "Volume"
  static let fetch: UInt16 = 64
  static let set: UInt16 = 64
  static let notify: UInt16 = 64

  static func updateInfo(d: Data, info: inout Device.Info) {
    guard let str = String(data: d, encoding: String.Encoding.utf8) else { return }
    guard let value = UInt8(str) else {
      logger.error("error parsing volume value \(str)")
      return
    }
    guard value <= 100 else {
      logger.error("volume value out of range: \(value)")
      return
    }

    info.volume = value
  }

  typealias DataType = UInt8
  static func marshalData(d: UInt8) -> Data {
    String(d > 100 ? 100 : d).data(using: String.Encoding.utf8)!
  }
}

struct PowerStateProperty: NotifyProperty, UpdateInfoProperty, SettableProperty {
  static let name = "Power state"
  static let fetch: UInt16 = 15
  static let set: UInt16 = 15
  static let notify: UInt16 = 15

  static func updateInfo(d: Data, info: inout Device.Info) {
    switch parseString(d) {
    case "00":
      info.powerState = .Awake
    case "02":
      info.powerState = .Sleeping
    default:
      logger.error("invalid PowerState value: \(d)")
    }
  }

  typealias DataType = Device.PowerStateValue
  static func marshalData(d: Device.PowerStateValue) -> Data {
    var str: String
    switch d {
    case .Awake:
      str = "00"
    case .Sleeping:
      str = "02"
    }

    return str.data(using: String.Encoding.utf8)!
  }
}

struct PlayingStateProperty: NotifyProperty, UpdateInfoProperty, SettableProperty {
  static let fetch: UInt16 = 51
  static let set: UInt16 = 40
  static let notify: UInt16 = 51
  static let name: String = "Playing state"

  static func updateInfo(d: Data, info: inout Device.Info) {
    guard d.count == 1 else {
      logger.error("Expected 1 byte for playing state change, got \(d.count)")
      return
    }

    var value: Device.PlayingStateChange

    // data is the ASCII code for a digit that is the 0 based command
    // index in the PlayingStateChange enum
    switch d[0] {
    case 48: value = .Play
    case 49: value = .Stop
    case 50: value = .Pause
    case 51: value = .Next
    case 52: value = .Previous
    case 53: value = .Toggle
    case 54: value = .Mute
    case 55: value = .Unmute
    default:
      logger.error("invalid playing state change value: \(d[0])")
      return
    }

    info.playingState = value
  }

  typealias DataType = Device.PlayingStateChange

  static func marshalData(d: Device.PlayingStateChange) -> Data {
    var str: String

    switch d {
    case .Play: str = "PLAY"
    case .Stop: str = "STOP"
    case .Pause: str = "PAUSE"
    case .Next: str = "NEXT"
    case .Previous: str = "PREV"
    case .Toggle: str = "TOGGL"
    case .Mute: str = "MUTE"
    case .Unmute: str = "UNMUTE"
    }

    return str.data(using: String.Encoding.utf8)!
  }
}

struct CurrentTrackProperty: NotifyProperty, UpdateInfoProperty, SettableProperty {
  static let fetch: UInt16 = 278
  static let set: UInt16 = 277
  static let notify: UInt16 = 278
  static let name: String = "Current track"

  static func updateInfo(d: Data, info: inout Device.Info) {
    guard let currentTrackJSON = try? JSONSerialization.jsonObject(with: d, options: []) else {
      logger.error("invalid JSON in current track data \(d)")
      return
    }

    guard let currentTrack = Device.CurrentTrackData(json: currentTrackJSON) else {
      logger.error("invalid current track data: \(d)")
      return
    }

    info.currentTrack = currentTrack
  }

  typealias DataType = Device.CurrentTrackData

  static func marshalData(d: Device.CurrentTrackData) -> Data {
    do {
      return try JSONSerialization.data(withJSONObject: d.toJSON())
    } catch {
      logger.error("error serializing current track data to JSON: \(error)")
      return Data()
    }
  }
}

extension Device.CurrentTrackData {
  init?(json: Any) {
    guard let json = json as? [String: Any] else { return nil }

    isFromChannel = json["isFromChannel"] as? Bool
    playAlbum = json["play_album"] as? String
    playAlbumURI = json["play_album_uri"] as? String
    playArtist = json ["play_artist"] as? String
    playAttribution = json["play_attribution"] as? String
    playIdentity = json["play_identity"] as? String
    playObject = json["play_object"] as? String
    playPic = json["play_pic"] as? String
    playPresetAvailable = json["play_preset_available"] as? Int
    playSubtitle = json["play_subtitle"] as? String
    playTitle = json["play_title"] as? String
    playType = json["play_type"] as? String
    playUsername = json["play_username"] as? String
    playToken = json["play_token"] as? String
  }

  public init(fromFavorite f: Device.Favorite) {
    self.playTitle = f.channelName
    self.playSubtitle = f.channelName
    self.playType = f.channelType?.rawValue
    self.playIdentity = f.channelIdentity
    self.playToken = f.playToken
  }

  func toJSON() -> [String: Any] {
    return [
      "isFromChannel": isFromChannel as Any,
      "play_album": playAlbum as Any,
      "play_album_uri": playAlbumURI as Any,
      "play_artist": playArtist as Any,
      "play_attribution": playAttribution as Any,
      "play_identity": playIdentity as Any,
      "play_object": playObject as Any,
      "play_pic": playPic as Any,
      "play_preset_available": playPresetAvailable as Any,
      "play_subtitle": playSubtitle as Any,
      "play_title": playTitle as Any,
      "play_type": playType as Any,
      "play_username": playUsername as Any,
      "play_token": playToken as Any
    ]
  }
}

struct FavoritesProperty: UpdateInfoProperty {
  static let fetch: UInt16 = 275
  static let name: String = "Favorites"

  static func updateInfo(d: Data, info: inout Device.Info) {
    guard let favoritesJSON = try? JSONSerialization.jsonObject(with: d, options: []) else {
      logger.error("invalid JSON in favorites data \(d)")
      return
    }

    guard let favoritesJSONArray = favoritesJSON as? [Any] else {
      logger.error("favorites data is not an array: \(d)")
      return
    }

    var favorites: [Device.Favorite] = []

    for j in favoritesJSONArray {
      if let f = Device.Favorite(json: j) {
        favorites.append(f)
      } else {
        logger.error("invalid favorite data: \(j)")
      }
    }

    info.favorites = favorites
  }
}

extension Device.Favorite {
  init?(json: Any) {
    guard let json = json as? [String: Any] else { return nil }

    isPlaying = json["isPlaying"] as? Bool
    channelID = json["channel_id"] as? String
    channelType = ChannelType(rawValue: json["channel_type"] as? String ?? "")
    channelName = json["channel_name"] as? String
    channelIdentity = json["channel_identity"] as? String
    stationURL = json["station_url"] as? String
    pictureURL = json["picture_url"] as? String
    username = json["username"] as? String
    password = json["password"] as? String
    playToken = json["play_token"] as? String
  }
}
