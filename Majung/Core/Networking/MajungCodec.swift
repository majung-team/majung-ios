import Foundation

enum MajungCodec {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]

        decoder.dateDecodingStrategy = .custom { container in
            let single = try container.singleValueContainer()
            let raw = try single.decode(String.self)
            if let date = fractional.date(from: raw) ?? plain.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: single,
                debugDescription: "Invalid ISO-8601 timestamp: \(raw)"
            )
        }
        return decoder
    }()

    static let encoder = JSONEncoder()
}
