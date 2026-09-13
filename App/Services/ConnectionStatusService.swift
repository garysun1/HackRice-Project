enum ConnectionState: Equatable, Sendable {
    case notConnected
    case connected
    case denied
    case unavailable
}

struct ConnectionStatusSnapshot: Equatable, Sendable {
    var health: ConnectionState = .notConnected
    var calendar: ConnectionState = .notConnected
    var location: ConnectionState = .notConnected
}
