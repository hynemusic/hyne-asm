import XCTest
@testable import HMLauncherCore

/// Small JSON tree used by the shared fixtures (spec/fixtures/*.json).
enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let d = try? c.decode(Double.self) { self = .number(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    /// Canonical text: 2-space indent, sorted keys, `"key": value`, no trailing newline.
    func pretty(indent: Int = 0) -> String {
        let pad = String(repeating: " ", count: indent + 2)
        let end = String(repeating: " ", count: indent)
        switch self {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .number(let d):
            if d == d.rounded(), abs(d) < 1e15 { return String(Int64(d)) }
            return "\(d)"
        case .string(let s): return JSONValue.quote(s)
        case .array(let a):
            if a.isEmpty { return "[]" }
            return "[\n" + a.map { pad + $0.pretty(indent: indent + 2) }.joined(separator: ",\n") + "\n" + end + "]"
        case .object(let o):
            if o.isEmpty { return "{}" }
            return "{\n" + o.keys.sorted().map { pad + JSONValue.quote($0) + ": " + o[$0]!.pretty(indent: indent + 2) }
                .joined(separator: ",\n") + "\n" + end + "}"
        }
    }

    private static func quote(_ s: String) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.withoutEscapingSlashes]
        let data = (try? enc.encode([s])) ?? Data("[\"\"]".utf8)
        let text = String(decoding: data, as: UTF8.self)
        return String(text.dropFirst().dropLast())
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }
}

final class SharedFixtureTests: XCTestCase {
    /// One handler per fixture area. Later tasks add entries here (and one on the C# side).
    static let handlers: [String: (JSONValue) throws -> JSONValue] = [
        "smoke.echo": { $0 },
    ]

    static var fixturesDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("spec/fixtures")
    }

    func testAllFixtures() throws {
        let recording = ProcessInfo.processInfo.environment["HM_RECORD_FIXTURES"] == "1"
        let files = try FileManager.default.contentsOfDirectory(at: Self.fixturesDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(files.isEmpty, "no fixtures found in \(Self.fixturesDir.path)")

        for file in files {
            let name = file.lastPathComponent
            var root = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file))
            guard case .string(let area)? = root["area"], case .array(var cases)? = root["cases"] else {
                XCTFail("\(name): needs \"area\" and \"cases\""); continue
            }
            let isHand: Bool = { if case .string("hand")? = root["reference"] { return true } else { return false } }()
            let handler = Self.handlers[area]
            if handler == nil {
                if isHand { continue }   // validated later, once a handler exists
                XCTFail("\(name): no Swift handler for area \(area)"); continue
            }
            var seen = Set<String>()
            for i in cases.indices {
                guard case .string(let caseName)? = cases[i]["name"] else { XCTFail("\(name): case \(i) has no name"); continue }
                XCTAssertTrue(seen.insert(caseName).inserted, "\(name): duplicate case name \(caseName)")
                let input = cases[i]["input"] ?? .null
                let actual = try handler!(input)
                if recording && !isHand {
                    guard case .object(var o) = cases[i] else { continue }
                    o["expected"] = actual
                    cases[i] = .object(o)
                } else {
                    XCTAssertEqual(actual, cases[i]["expected"] ?? .null, "\(name) / \(area) / \(caseName)")
                }
            }
            if recording && !isHand, case .object(var r) = root {
                r["cases"] = .array(cases)
                root = .object(r)
                try (root.pretty() + "\n").write(to: file, atomically: true, encoding: .utf8)
            }
        }
    }
}
