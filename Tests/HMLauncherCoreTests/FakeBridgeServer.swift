import Foundation
import Network

/// Local TCP server speaking the bridge's line protocol. `respond` gets the parsed request and
/// returns the reply object (or nil to stay silent).
final class FakeBridgeServer: @unchecked Sendable {
    private(set) var port: UInt16 = 0
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let queue = DispatchQueue(label: "fake-bridge")
    var respond: ([String: Any]) -> [String: Any]? = { _ in nil }
    var chunkSize: Int? = nil
    var reverseOrder = false
    var replyDelay: TimeInterval = 0
    private var held: [(NWConnection, Data)] = []

    func start(port fixed: UInt16 = 0) throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: fixed) ?? .any)
        let ready = DispatchSemaphore(value: 0)
        l.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        l.start(queue: queue)
        guard ready.wait(timeout: .now() + 2) == .success else { throw URLError(.cannotConnectToHost) }
        port = l.port!.rawValue
        listener = l
    }

    func stop() {
        queue.sync {
            listener?.cancel(); listener = nil
            connections.forEach { $0.cancel() }; connections = []
        }
    }

    private func accept(_ c: NWConnection) {
        connections.append(c)
        c.start(queue: queue)
        read(c, buffer: Data())
    }

    private func read(_ c: NWConnection, buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, err in
            guard let self, err == nil else { return }
            var buf = buffer + (data ?? Data())
            while let nl = buf.firstIndex(of: 0x0A) {
                let line = buf[buf.startIndex..<nl]
                buf = Data(buf[buf.index(after: nl)...])
                if let req = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                   let reply = self.respond(req) {
                    var out = try! JSONSerialization.data(withJSONObject: reply)
                    out.append(0x0A)
                    if self.reverseOrder {
                        self.held.append((c, out))
                        if self.held.count == 2 { self.held.reversed().forEach { self.send($0.1, on: $0.0) }; self.held = [] }
                    } else if self.replyDelay > 0 {
                        self.queue.asyncAfter(deadline: .now() + self.replyDelay) { self.send(out, on: c) }
                    } else {
                        self.send(out, on: c)
                    }
                }
            }
            if !done { self.read(c, buffer: buf) }
        }
    }

    private func send(_ data: Data, on c: NWConnection) {
        guard let size = chunkSize else { c.send(content: data, completion: .contentProcessed { _ in }); return }
        var offset = 0
        while offset < data.count {
            let end = min(offset + size, data.count)
            c.send(content: data[offset..<end], completion: .contentProcessed { _ in })
            offset = end
        }
    }
}

func ok(_ req: [String: Any], _ result: Any? = nil) -> [String: Any] {
    ["id": req["id"]!, "ok": true, "result": result ?? NSNull(), "error": NSNull()]
}

func waitUntil(_ timeout: TimeInterval = 3, _ condition: () async -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return await condition()
}
