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
