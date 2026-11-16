import Foundation
import Network

public struct HelloResult: Decodable, Sendable {
    public let scriptVersion: String
    public let liveVersion: String
}

public enum BridgeError: Error, Equatable, Sendable {
    case notConnected, timeout
    case remote(String)
}

private struct Envelope<R: Decodable>: Decodable {
    let ok: Bool
    let result: R?
    let error: String?
}

private struct Empty: Decodable {}
private struct ItemsResult: Decodable { let items: [PluginItem] }
private struct IDOnly: Decodable { let id: Int? }

/// TCP client for the HMLauncherBridge remote script (newline-delimited JSON on 127.0.0.1:47820).
/// Reconnects automatically while started.
public actor BridgeClient {
    private let host: String
    private let port: UInt16
    private let requestTimeout: TimeInterval
    /// load replies only after Live finished loading (heavy M4L/instruments take seconds).
    private let loadTimeout: TimeInterval
    private let reconnectInterval: TimeInterval
    private let queue = DispatchQueue(label: "hm.bridge.client")

    private var connection: NWConnection?
    private var started = false
    private var buffer = Data()
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var handler: (@Sendable (Bool) -> Void)?
    public private(set) var isConnected = false

    public init(host: String = "127.0.0.1", port: UInt16 = 47820, requestTimeout: TimeInterval = 3, loadTimeout: TimeInterval = 30, reconnectInterval: TimeInterval = 2) {
        self.host = host
        self.port = port
        self.requestTimeout = requestTimeout
        self.loadTimeout = loadTimeout
        self.reconnectInterval = reconnectInterval
    }

    public func setConnectionHandler(_ h: @Sendable @escaping (Bool) -> Void) { handler = h }

    public func start() {
        guard !started else { return }
        started = true
        connect()
    }

    public func stop() {
        started = false
        teardown()
    }

    public func hello() async throws -> HelloResult {
        try decode(HelloResult.self, try await request(["cmd": "hello"]))
    }

    public func listItems() async throws -> [PluginItem] {
        try decode(ItemsResult.self, try await request(["cmd": "list"])).items
    }

    public func load(uri: String) async throws {
        _ = try decode(Empty.self, try await request(["cmd": "load", "uri": uri], timeout: loadTimeout), resultOptional: true)
    }

    // MARK: - Requests

    private func request(_ body: [String: Any], timeout: TimeInterval? = nil) async throws -> Data {
        guard isConnected, let connection else { throw BridgeError.notConnected }
        let id = nextID
        nextID += 1
        var message = body
        message["id"] = id
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(0x0A)
        let timeout = timeout ?? requestTimeout
        return try await withCheckedThrowingContinuation { cont in
            pending[id] = cont
            connection.send(content: data, completion: .contentProcessed { _ in })
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                await self?.fail(id, with: .timeout)
            }
        }
    }

    private func fail(_ id: Int, with error: BridgeError) {
        pending.removeValue(forKey: id)?.resume(throwing: error)
    }

    private func decode<R: Decodable>(_ type: R.Type, _ line: Data, resultOptional: Bool = false) throws -> R {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let env = try decoder.decode(Envelope<R>.self, from: line)
        guard env.ok else { throw BridgeError.remote(env.error ?? "unknown") }
        if let result = env.result { return result }
        if resultOptional, let empty = Empty() as? R { return empty }
        throw BridgeError.remote("missing_result")
    }

    // MARK: - Connection

    private func connect() {
        guard started, connection == nil, let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        connection = conn
        conn.stateUpdateHandler = { [weak self] state in
            Task { await self?.handle(state, of: conn) }
        }
        conn.start(queue: queue)
    }

    private func handle(_ state: NWConnection.State, of conn: NWConnection) {
        guard conn === connection else { return }
        switch state {
        case .ready:
            setConnected(true)
            receive(on: conn)
        case .failed, .waiting, .cancelled:
            teardown()
            scheduleReconnect()
        default:
            break
        }
    }

    private func receive(on conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { await self?.didReceive(data, complete: isComplete || error != nil, on: conn) }
        }
    }

    private func didReceive(_ data: Data?, complete: Bool, on conn: NWConnection) {
        guard conn === connection else { return }
        if let data { buffer.append(data) }
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[buffer.startIndex..<nl])
            buffer = Data(buffer[buffer.index(after: nl)...])
            if let id = (try? JSONDecoder().decode(IDOnly.self, from: line))?.id {
                pending.removeValue(forKey: id)?.resume(returning: line)
            }
        }
        if complete {
            teardown()
            scheduleReconnect()
        } else {
            receive(on: conn)
        }
    }

    private func teardown() {
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        buffer = Data()
        let waiting = pending
        pending = [:]
        waiting.values.forEach { $0.resume(throwing: BridgeError.notConnected) }
        setConnected(false)
    }

    private func scheduleReconnect() {
        guard started else { return }
        let delay = reconnectInterval
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await self?.connect()
        }
    }

    private func setConnected(_ value: Bool) {
        guard value != isConnected else { return }
        isConnected = value
        handler?(value)
    }
}
