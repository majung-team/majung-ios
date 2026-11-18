import CoreLocation
import Foundation
import MapKit

struct PlaceSearchCandidate: Identifiable, Hashable {
    enum Source: String, Hashable {
        case kakao
        case mapKit
    }

    let id: String
    let label: String
    let address: String?
    let category: String?
    let latitude: Double
    let longitude: Double
    let source: Source

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var pickupPlace: PickupPlace {
        PickupPlace(label: String(label.prefix(60)), latitude: latitude, longitude: longitude)
    }

    var detailText: String {
        let trimmedAddress = address?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedAddress, !trimmedAddress.isEmpty {
            return trimmedAddress
        }
        return "주소 정보 없음 · 지도에서 위치를 확인해주세요"
    }
}

struct PlaceSearchAPIResponse: Decodable, Equatable {
    struct Item: Decodable, Equatable {
        let label: String
        let address: String?
        let category: String?
        let latitude: Double
        let longitude: Double
    }

    let enabled: Bool
    let items: [Item]
    let hasNext: Bool
}

struct PlaceSearchResultPage: Equatable {
    let candidates: [PlaceSearchCandidate]
    let hasNext: Bool
    let usedFallback: Bool
}

enum PlaceSearchService {
    private static let defaultSession = URLSession(configuration: .ephemeral)

    static func searchURL(
        query: String,
        page: Int = 1,
        near center: CLLocationCoordinate2D? = nil,
        baseURL: URL = APIBaseURL.root
    ) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let clampedPage = min(max(page, 1), 3)
        let endpoint = baseURL.appendingPathComponent("places").appendingPathComponent("search")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return nil }
        var queryItems = [
            URLQueryItem(name: "query", value: String(trimmed.prefix(80))),
            URLQueryItem(name: "page", value: String(clampedPage))
        ]
        if let center {
            queryItems.append(URLQueryItem(name: "latitude", value: String(center.latitude)))
            queryItems.append(URLQueryItem(name: "longitude", value: String(center.longitude)))
        }
        components.queryItems = queryItems
        return components.url
    }

    static func search(
        query: String,
        page: Int = 1,
        near center: CLLocationCoordinate2D? = nil,
        baseURL: URL = APIBaseURL.root,
        session: URLSession = defaultSession,
        mapKitFallback: ((String, CLLocationCoordinate2D?) async throws -> [PlaceSearchCandidate])? = nil
    ) async throws -> PlaceSearchResultPage {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let clampedPage = min(max(page, 1), 3)
        guard !trimmed.isEmpty else {
            return PlaceSearchResultPage(candidates: [], hasNext: false, usedFallback: false)
        }

        if let url = searchURL(query: trimmed, page: clampedPage, near: center, baseURL: baseURL) {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            do {
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse,
                   (200..<300).contains(http.statusCode),
                   let decoded = try? MajungCodec.decoder.decode(PlaceSearchAPIResponse.self, from: data),
                   decoded.enabled {
                    let mapped = decoded.items.enumerated().map { index, item in
                        let cleanedLabel = item.label.trimmingCharacters(in: .whitespacesAndNewlines)
                        let displayLabel = cleanedLabel.isEmpty ? trimmed : cleanedLabel
                        return PlaceSearchCandidate(
                            id: "kakao-\(clampedPage)-\(index)-\(displayLabel)-\(item.latitude)-\(item.longitude)",
                            label: String(displayLabel.prefix(60)),
                            address: item.address,
                            category: item.category,
                            latitude: item.latitude,
                            longitude: item.longitude,
                            source: .kakao
                        )
                    }
                    if !mapped.isEmpty {
                        return PlaceSearchResultPage(
                            candidates: mapped,
                            hasNext: decoded.hasNext && clampedPage < 3,
                            usedFallback: false
                        )
                    }
                    if clampedPage > 1 {
                        return PlaceSearchResultPage(candidates: [], hasNext: false, usedFallback: false)
                    }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Fall back to MapKit on transient server or network failure when searching page 1.
            }
        }

        guard clampedPage == 1 else {
            return PlaceSearchResultPage(candidates: [], hasNext: false, usedFallback: true)
        }

        let fallback = mapKitFallback ?? searchMapKit
        let mapKitItems = try await fallback(trimmed, center)
        return PlaceSearchResultPage(candidates: mapKitItems, hasNext: false, usedFallback: true)
    }

    static func searchMapKit(query: String, near center: CLLocationCoordinate2D? = nil) async throws -> [PlaceSearchCandidate] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let center {
            request.region = MKCoordinateRegion(
                center: center,
                latitudinalMeters: 12_000,
                longitudinalMeters: 12_000
            )
        }
        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems.prefix(15).enumerated().map { index, item in
                let coord = item.placemark.coordinate
                let rawLabel = item.name ?? item.placemark.title ?? query
                return PlaceSearchCandidate(
                    id: "mapkit-\(index)-\(rawLabel)-\(coord.latitude)-\(coord.longitude)",
                    label: String(rawLabel.prefix(60)),
                    address: item.placemark.title,
                    category: nil,
                    latitude: coord.latitude,
                    longitude: coord.longitude,
                    source: .mapKit
                )
            }
        } catch let error as MKError where error.code == .placemarkNotFound {
            return []
        }
    }

    static func place(from item: MKMapItem, fallbackLabel: String) -> PickupPlace {
        let rawLabel = item.name ?? item.placemark.title ?? fallbackLabel
        return PickupPlace(
            label: String(rawLabel.prefix(60)),
            latitude: item.placemark.coordinate.latitude,
            longitude: item.placemark.coordinate.longitude
        )
    }
}
