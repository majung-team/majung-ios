import Foundation
import Observation

#if DEBUG
enum DevServerMode: String, CaseIterable, Identifiable {
    case production
    case demo
    case local

    var id: String { rawValue }

    var title: String {
        switch self {
        case .production: "운영 서버 (majung.cloud)"
        case .demo: "앱 내 데모 (혼자 테스트)"
        case .local: "내 Mac 로컬 서버"
        }
    }

    var shortLabel: String {
        switch self {
        case .production: "운영 서버"
        case .demo: "앱 내 데모"
        case .local: "로컬 서버"
        }
    }
}

@MainActor
@Observable
final class DevServerConfig {
    static let shared = DevServerConfig()

    private let modeKey = "majung.debug.serverMode"
    private let localOriginKey = "majung.debug.localOrigin"

    var mode: DevServerMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: modeKey)
        }
    }

    var localOrigin: String {
        didSet {
            UserDefaults.standard.set(localOrigin, forKey: localOriginKey)
        }
    }

    private init() {
        let rawMode = UserDefaults.standard.string(forKey: modeKey)
        self.mode = rawMode.flatMap(DevServerMode.init(rawValue:)) ?? .production
        let savedOrigin = UserDefaults.standard.string(forKey: localOriginKey)
        self.localOrigin = savedOrigin?.isEmpty == false ? savedOrigin! : "http://127.0.0.1:8080"
    }
}
#endif

enum APIBaseURL {
    #if DEBUG
    private static let modeKey = "majung.debug.serverMode"
    private static let localOriginKey = "majung.debug.localOrigin"
    #endif

    static var root: URL {
        #if DEBUG && targetEnvironment(simulator)
        if let port = ProcessInfo.processInfo.environment["MAJUNG_TEST_PORT"].flatMap(Int.init),
           (1...65535).contains(port) {
            return URL(string: "http://localhost:\(port)/api/v1")!
        }
        #endif
        #if DEBUG
        let mode = UserDefaults.standard.string(forKey: modeKey).flatMap(DevServerMode.init(rawValue:)) ?? .production
        switch mode {
        case .production:
            break
        case .demo:
            let port = SoloDemoServer.shared.ensureStarted()
            if port > 0, let url = URL(string: "http://127.0.0.1:\(port)/api/v1") {
                return url
            }
        case .local:
            let raw = (UserDefaults.standard.string(forKey: localOriginKey) ?? "http://127.0.0.1:8080")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if var parsed = URL(string: raw.isEmpty ? "http://127.0.0.1:8080" : raw),
               let scheme = parsed.scheme?.lowercased(),
               scheme == "http" || scheme == "https" {
                let path = parsed.path
                if path.isEmpty || path == "/" {
                    parsed.appendPathComponent("api")
                    parsed.appendPathComponent("v1")
                }
                return parsed
            }
            return URL(string: "http://127.0.0.1:8080/api/v1")!
        }
        #endif
        return URL(string: "https://majung.cloud/api/v1")!
    }
}

final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

enum MajungEventStream {
    static func listen(
        request: URLRequest,
        session: URLSession,
        onState: @escaping @MainActor (Bool) -> Void,
        onRefresh: @escaping @MainActor () async -> Void
    ) async {
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
                  contentType.contains("text/event-stream") else {
                await onState(false)
                return
            }

            await onState(true)
            var currentEvent = "message"
            var dataLines: [String] = []
            var lineBytes: [UInt8] = []
            var justProcessedCR = false

            func processLine(_ rawBytes: [UInt8]) async -> Bool {
                let line = String(decoding: rawBytes, as: UTF8.self)
                if line.isEmpty {
                    let payload = dataLines.joined(separator: "\n")
                    if currentEvent == "changed", payload == "refresh" {
                        await onRefresh()
                    } else if currentEvent == "access-ended" {
                        await onRefresh()
                        return true
                    }
                    currentEvent = "message"
                    dataLines.removeAll()
                } else if line.hasPrefix("event:") {
                    currentEvent = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("data:") {
                    var value = String(line.dropFirst(5))
                    if value.hasPrefix(" ") { value.removeFirst() }
                    dataLines.append(value)
                }
                return false
            }

            for try await byte in bytes {
                if Task.isCancelled { break }
                if byte == 0x0A {
                    if justProcessedCR {
                        justProcessedCR = false
                        continue
                    }
                    let shouldBreak = await processLine(lineBytes)
                    lineBytes.removeAll(keepingCapacity: true)
                    if shouldBreak { break }
                } else if byte == 0x0D {
                    justProcessedCR = true
                    let shouldBreak = await processLine(lineBytes)
                    lineBytes.removeAll(keepingCapacity: true)
                    if shouldBreak { break }
                } else {
                    justProcessedCR = false
                    lineBytes.append(byte)
                }
            }
        } catch {
            // Polling handles transient SSE disconnects.
        }
        await onState(false)
    }
}
