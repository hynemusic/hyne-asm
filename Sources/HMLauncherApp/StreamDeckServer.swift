import Foundation
import Network
import HMLauncherCore

/// Local HTTP endpoint for Stream Deck's "Website" action (with "Access in background", so no browser opens).
/// Listens on 127.0.0.1 only — nothing outside this Mac can reach it — and only while switched on in Behavior.
@MainActor
final class StreamDeckServer: ObservableObject {
    enum State: Equatable { case off, listening, failed(String) }
    @Published private(set) var state: State = .off
    var onCommand: (RemoteCommand) -> Void = { _ in }
    private var listener: NWListener?

    func setEnabled(_ enabled: Bool) {
        enabled ? start() : stop()
    }

    private func start() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: RemoteCommand.httpPort)!)
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params)
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready: self?.state = .listening
                    case .failed(let error): self?.state = .failed(error.localizedDescription); self?.stop(keepState: true)
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.serve(connection) }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func stop(keepState: Bool = false) {
        listener?.cancel()
        listener = nil
        if !keepState { state = .off }
    }

    /// Reads one request line ("GET /insert?name=Serum%202 HTTP/1.1"), runs it, answers and closes.
    private func serve(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            Task { @MainActor in
                let line = data.flatMap { String(data: $0, encoding: .utf8) }?.split(separator: "\r\n").first ?? ""
                let parts = line.split(separator: " ")
                var status = "400 Bad Request", body = "bad request"
                if parts.count >= 2, parts[0] == "GET",
                   let url = URL(string: "http://127.0.0.1:\(RemoteCommand.httpPort)" + parts[1]) {
                    if let command = RemoteCommand(url: url) {
                        self?.onCommand(command)
                        status = "200 OK"; body = "ok"
                    } else {
                        status = "404 Not Found"; body = "unknown command"
                    }
                }
                let response = "HTTP/1.1 \(status)\r\nContent-Type: text/plain\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
    }
}
