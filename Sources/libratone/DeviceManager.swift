import Foundation
import Network

public class DeviceManager {
  var knownDevices: [NWEndpoint.Host: Device] = [:]
  public var deviceDiscoveredHandler: ((Device) -> Void)? = nil
  public var deviceDisappearedHandler: ((NWEndpoint.Host) -> Void)? = nil

  public init() {
    // logger.logLevel = .debug
  }

  public func start(queue: DispatchQueue) throws {
    try startDiscovery(queue: queue)
    try startListener(
      queue: queue,
      port: 3333,
      name: "notify",
      packetHandler: { (host, packet) in
        self.knownDevices[host]?.handleNotify(packet: packet)
      }
    )
    try startListener(
      queue: queue,
      port: 7778,
      name: "command response",
      packetHandler: { (host, packet) in
        self.knownDevices[host]?.handleReply(packet: packet)
      }
    )
  }

  func startDiscovery(queue: DispatchQueue) throws {
    let listenEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host.ipv4(IPv4Address("239.255.255.250")!), port: 1800)
    let group = try NWConnectionGroup(with: NWMulticastGroup(for: [listenEndpoint]), using: NWParameters.udp)

    group.setReceiveHandler(maximumMessageSize: 65536, rejectOversizedMessages: true) { message, content, isComplete in
      guard isComplete else { return }
      guard content != nil else { return }
      guard message.remoteEndpoint != nil else { return }

      logger.debug("Got \(content!.count) bytes from \(message.remoteEndpoint!)")

      guard let ssdpMessage = try? SSDP.Message.parse(content!) else {
        logger.error("Error parsing SSDP message")
        return
      }

      switch ssdpMessage {
      case .Search:
        return
      case .Notify(let headers):
        guard case let .hostPort(host, _) = message.remoteEndpoint! else {
          logger.error("Cannot handle device endpoint: \(message.remoteEndpoint!)")
          return
        }

        DispatchQueue.main.async {
          guard self.knownDevices[host] == nil else {
            return // we already know that device
          }

          logger.debug("Discovered new device: \(headers)")
          let d = Device(queue: queue, host: host)
          self.knownDevices[host] = d
          self.deviceDiscoveredHandler?(d)
        }
      }
    }

    group.start(queue: queue)

    group.send(content: SSDP.Message.Search.data()) { err in if err != nil { logger.error("Error sending M-SEARCH: \(err!)") }}
  }

  private typealias PacketHandler = (NWEndpoint.Host, Proto.Packet) -> Void

  private func startListener(queue: DispatchQueue, port: NWEndpoint.Port, name: String, packetHandler: @escaping PacketHandler) throws {
    let listener = try NWListener(using: NWParameters.udp, on: port)
    listener.stateUpdateHandler = listenerStateLogger(name: name)
    listener.newConnectionHandler = { conn in
      DispatchQueue.main.async {
        self.connectionHandler(queue: queue, conn: conn, packetHandler: packetHandler)
      }
    }
    listener.start(queue: queue)
  }

  private func listenerStateLogger(name: String) -> (NWListener.State) -> Void {
    { state in
      switch state {
      case .failed(let err):
        logger.debug("Listening for \(name) packets failed: \(err)")
      case .ready:
        logger.debug("Listening for \(name) packets")
      default:
        break
      }
    }
  }

  private func connectionHandler(queue: DispatchQueue, conn: NWConnection, packetHandler: @escaping PacketHandler) {
    guard case let .hostPort(host: host, port: _) = conn.endpoint else {
      assertionFailure("endpoint is not a host:port")
      return
    }
    guard self.knownDevices[host] != nil else {
      logger.debug("Ignoring message from unknown device \(conn.endpoint)")
      return
    }

    conn.stateUpdateHandler = { state in
      switch (state) {
      case .failed(let err):
        logger.error("Connection with \(conn.endpoint) failed: \(err)")
      case .ready:
        self.receiveForever(conn, packetHandler)
      default:
        break
      }
    }

    conn.start(queue: queue)
  }

  private func receiveForever(_ conn: NWConnection, _ packetHandler: @escaping PacketHandler) {
    guard case let .hostPort(host: host, port: _) = conn.endpoint else {
      assertionFailure("endpoint is not a host:port")
      return
    }

    conn.receiveMessage() { content, context, isComplete, err in
      guard err == nil else {
        logger.error("Error receiving message from \(conn.endpoint): \(err!). Forgetting device.")
        conn.forceCancel()

        DispatchQueue.main.async {
          self.deviceDisappearedHandler?(host)
          self.knownDevices.removeValue(forKey: host)
        }

        return
      }

      defer { self.receiveForever(conn, packetHandler) }

      if isComplete && content != nil {
        do {
          let packet = try Proto.Packet(content!)

          DispatchQueue.main.async {
            packetHandler(host, packet)
          }

        } catch {
          logger.error("Error parsing packet from \(conn.endpoint): \(error)")
          return
        }
      }
    }
  }
}
