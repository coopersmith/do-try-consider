import Foundation

final class GranolaAPIClient: Sendable {
    static let shared = GranolaAPIClient()

    private let baseURL = "https://public-api.granola.ai/v1"
    private let session = URLSession.shared
    private let maxRetries = 3

    private init() {}

    // MARK: - Notes

    func listNotes(
        since: Date? = nil,
        until: Date? = nil,
        cursor: String? = nil,
        limit: Int = 25
    ) async throws -> GranolaNotesResponse {
        var queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
        ]

        if let since {
            queryItems.append(URLQueryItem(name: "since", value: ISO8601DateFormatter().string(from: since)))
        }
        if let until {
            queryItems.append(URLQueryItem(name: "until", value: ISO8601DateFormatter().string(from: until)))
        }
        if let cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }

        return try await request(path: "/notes", queryItems: queryItems)
    }

    func getNote(id: String) async throws -> GranolaNoteDetail {
        return try await request(path: "/notes/\(id)")
    }

    func getNoteWithTranscript(id: String) async throws -> GranolaNoteDetail {
        return try await request(
            path: "/notes/\(id)",
            queryItems: [URLQueryItem(name: "include", value: "transcript")]
        )
    }

    func getRecentNotes(days: Int = 7) async throws -> [GranolaNoteListItem] {
        let since = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let response = try await listNotes(since: since)
        return response.notes
    }

    func getTodaysMeetings() async throws -> [GranolaNoteListItem] {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let response = try await listNotes(since: startOfDay)
        return response.notes
    }

    func searchNotes(query: String, days: Int = 30) async throws -> [GranolaNoteListItem] {
        let notes = try await getRecentNotes(days: days)
        let lowered = query.lowercased()
        return notes.filter { note in
            (note.title ?? "").lowercased().contains(lowered)
        }
    }

    // MARK: - Generic Request

    private func request<T: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        retryCount: Int = 0
    ) async throws -> T {
        guard let apiKey = try TokenManager.shared.getGranolaAPIKey(), !apiKey.isEmpty else {
            throw GranolaAPIError.noAPIKey
        }

        var components = URLComponents(string: baseURL + path)!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GranolaAPIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                print("Granola decode error: \(error)")
                print("Raw response: \(String(data: data, encoding: .utf8)?.prefix(500) ?? "nil")")
                throw error
            }

        case 401:
            throw GranolaAPIError.unauthorized

        case 404:
            throw GranolaAPIError.notFound

        case 429:
            guard retryCount < maxRetries else {
                throw GranolaAPIError.rateLimited
            }
            let delay = pow(2.0, Double(retryCount + 1))
            try await Task.sleep(for: .seconds(delay))
            return try await self.request(path: path, queryItems: queryItems, retryCount: retryCount + 1)

        default:
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GranolaAPIError.serverError(httpResponse.statusCode, errorBody)
        }
    }
}

enum GranolaAPIError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case unauthorized
    case rateLimited
    case notFound
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No Granola API key configured. Add your key in Settings."
        case .invalidResponse: return "Invalid response from Granola."
        case .unauthorized: return "Invalid Granola API key. Requires Enterprise plan."
        case .rateLimited: return "Too many requests to Granola. Please try again later."
        case .notFound: return "Meeting not found."
        case .serverError(let code, let body): return "Granola error (\(code)): \(body)"
        }
    }
}
