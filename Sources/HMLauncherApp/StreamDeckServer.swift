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

    /// The install's link token (from the config); requests without it are refused.
    var token = ""

    /// Reads the request (line + headers, max 8 KB, 2 s), checks it, runs it, answers and closes.
    private func serve(_ connection: NWConnection) {
        connection.start(queue: .main)
        let deadline = DispatchWorkItem { connection.cancel() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: deadline)
        read(connection, buffer: Data(), deadline: deadline)
    }

    private func read(_ connection: NWConnection, buffer: Data, deadline: DispatchWorkItem) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, done, error in
            Task { @MainActor in
                guard let self else { return }
                var buffer = buffer
                if let data { buffer.append(data) }
                let text = String(decoding: buffer, as: UTF8.self)
                if !RemoteRequest.isComplete(text), !done, error == nil, buffer.count < 8192 {
                    self.read(connection, buffer: buffer, deadline: deadline)
                    return
                }
                deadline.cancel()
                let status: String, body: String
                switch RemoteRequest.handle(text, token: self.token) {
                case .run(let command): self.onCommand(command); status = "200 OK"; body = "ok"
                case .refused: status = "403 Forbidden"; body = "forbidden"
                case .unknown: status = "404 Not Found"; body = "unknown command"
                case .badRequest: status = "400 Bad Request"; body = "bad request"
                }
                let response = "HTTP/1.1 \(status)\r\nContent-Type: text/plain\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
    }
}
