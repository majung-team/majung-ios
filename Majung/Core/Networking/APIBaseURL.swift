import Foundation

enum APIBaseURL {
    static let root: URL = {
        #if DEBUG && targetEnvironment(simulator)
        if let port = ProcessInfo.processInfo.environment["MAJUNG_TEST_PORT"].flatMap(Int.init),
           (1...65535).contains(port) {
            return URL(string: "http://localhost:\(port)/api/v1")!
        }
        #endif
        return URL(string: "https://majung.cloud/api/v1")!
    }()
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
