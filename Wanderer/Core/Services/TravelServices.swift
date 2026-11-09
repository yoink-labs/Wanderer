import Foundation
import MapKit

struct MapSearchResult: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let address: String?
    let latitude: Double
    let longitude: Double
    let phone: String?
    let website: String?
    let category: PlaceCategory

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum MapSearchService {
    static func search(_ query: String, near coordinate: CLLocationCoordinate2D?) async throws -> [MapSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.pointOfInterest, .address]

        if let coordinate {
            request.region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 60_000,
                longitudinalMeters: 60_000
            )
        }

        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.compactMap { item in
            guard let name = item.name else { return nil }
            let placemark = item.placemark
            let category = category(for: item.pointOfInterestCategory)
            return MapSearchResult(
                name: name,
                address: placemark.title,
                latitude: placemark.coordinate.latitude,
                longitude: placemark.coordinate.longitude,
                phone: item.phoneNumber,
                website: item.url?.absoluteString,
                category: category
            )
        }
    }

    static func category(for category: MKPointOfInterestCategory?) -> PlaceCategory {
        guard let category else { return .sight }
        switch category {
        case .restaurant, .cafe, .bakery, .brewery, .winery, .foodMarket:
            return .food
        case .hotel, .campground:
            return .lodging
        case .museum, .park, .nationalPark, .zoo, .aquarium, .theater, .movieTheater, .amusementPark, .stadium:
            return .sight
        case .store:
            return .shopping
        case .publicTransport, .airport, .parking, .gasStation, .evCharger:
            return .transport
        case .fitnessCenter, .beach, .marina:
            return .activity
        default:
            return .sight
        }
    }
}

enum WeatherService {
    struct Snapshot {
        let temperature: Double
        let code: Int
    }

    static func current(latitude: Double, longitude: Double) async throws -> Snapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let payload = try JSONDecoder().decode(WeatherPayload.self, from: data)
        return Snapshot(temperature: payload.current.temperature, code: payload.current.code)
    }

    static func symbol(for code: Int) -> String {
        switch code {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...67: return "cloud.rain.fill"
        case 71...77: return "cloud.snow.fill"
        case 80...82: return "cloud.heavyrain.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.sun.fill"
        }
    }

    static func summary(for code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1, 2: return "Partly cloudy"
        case 3: return "Cloudy"
        case 45, 48: return "Fog"
        case 51...67: return "Rain"
        case 71...77: return "Snow"
        case 80...82: return "Showers"
        case 95...99: return "Storms"
        default: return "Mild"
        }
    }

    private struct WeatherPayload: Decodable {
        let current: Current
        struct Current: Decodable {
            let temperature: Double
            let code: Int

            enum CodingKeys: String, CodingKey {
                case temperature = "temperature_2m"
                case code = "weather_code"
            }
        }
    }
}

enum CurrencyService {
    static func rate(from: String, to: String) async throws -> Double? {
        guard from != to else { return 1 }
        var components = URLComponents(string: "https://api.frankfurter.app/latest")!
        components.queryItems = [
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to)
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let payload = try JSONDecoder().decode(RatePayload.self, from: data)
        return payload.rates[to]
    }

    private struct RatePayload: Decodable {
        let rates: [String: Double]
    }
}
