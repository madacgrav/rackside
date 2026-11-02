import Foundation

/// WatchConnectivity payloads: one `Codable` value as `Data` under a single key,
/// tagged with its kind, so nothing non-Sendable crosses actor boundaries.
enum SyncCodec {
    static let payloadKey = "payload"
    static let kindKey = "kind"

    static func encode<T: Encodable>(_ value: T, kind: String) throws -> [String: Any] {
        [payloadKey: try JSONEncoder().encode(value), kindKey: kind]
    }

    static func decode<T: Decodable>(_ type: T.Type, from dict: [String: Any], kind: String) -> T? {
        guard dict[kindKey] as? String == kind, let data = dict[payloadKey] as? Data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
