import Foundation

final class AsanaAPIClient: Sendable {
    static let shared = AsanaAPIClient()

    private let baseURL = "https://app.asana.com/api/1.0"
    private let session = URLSession.shared
    private let maxRetries = 3

    private init() {}

    // MARK: - Workspaces

    func getWorkspaces(accountID: String) async throws -> [AsanaWorkspace] {
        let response: AsanaResponse<[AsanaWorkspace]> = try await request(
            path: "/workspaces",
            queryItems: [URLQueryItem(name: "opt_fields", value: "name,is_organization")],
            accountID: accountID
        )
        return response.data
    }

    // MARK: - User

    func getCurrentUser(accountID: String) async throws -> AsanaUser {
        let response: AsanaResponse<AsanaUser> = try await request(
            path: "/users/me",
            queryItems: [URLQueryItem(name: "opt_fields", value: "name,email,photo,workspaces")],
            accountID: accountID
        )
        return response.data
    }

    // MARK: - Tasks

    func getMyTasks(
        workspaceID: String,
        completedSince: Date? = nil,
        modifiedSince: Date? = nil,
        accountID: String
    ) async throws -> [AsanaTask] {
        var queryItems = [
            URLQueryItem(name: "assignee", value: "me"),
            URLQueryItem(name: "workspace", value: workspaceID),
            URLQueryItem(name: "opt_fields", value: "name,notes,completed,completed_at,due_on,due_at,start_on,created_at,modified_at,projects.name,workspace.name,parent.name,permalink_url"),
        ]

        if let completedSince {
            queryItems.append(URLQueryItem(name: "completed_since", value: ISO8601DateFormatter().string(from: completedSince)))
        }

        let response: AsanaResponse<[AsanaTask]> = try await request(
            path: "/tasks",
            queryItems: queryItems,
            accountID: accountID
        )
        return response.data
    }

    func getTasksDueInRange(
        workspaceID: String,
        startDate: Date,
        endDate: Date,
        accountID: String
    ) async throws -> [AsanaTask] {
        let response: AsanaResponse<[AsanaTask]> = try await request(
            path: "/tasks",
            queryItems: [
                URLQueryItem(name: "assignee", value: "me"),
                URLQueryItem(name: "workspace", value: workspaceID),
                URLQueryItem(name: "completed_since", value: "now"),
                URLQueryItem(name: "opt_fields", value: "name,notes,completed,completed_at,due_on,due_at,start_on,projects.name,workspace.name,permalink_url"),
            ],
            accountID: accountID
        )

        return response.data.filter { task in
            guard let dueDate = task.dueDate else { return false }
            return dueDate >= startDate && dueDate <= endDate
        }
    }

    func getOverdueTasks(workspaceID: String, accountID: String) async throws -> [AsanaTask] {
        let tasks = try await getMyTasks(workspaceID: workspaceID, completedSince: Date(), accountID: accountID)
        return tasks.filter { $0.isOverdue }
    }

    func getTasksCompletedToday(workspaceID: String, accountID: String) async throws -> [AsanaTask] {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let tasks = try await getMyTasks(workspaceID: workspaceID, completedSince: startOfToday, accountID: accountID)
        return tasks.filter { $0.completed == true }
    }

    func getTask(id: String, accountID: String) async throws -> AsanaTask {
        let response: AsanaResponse<AsanaTask> = try await request(
            path: "/tasks/\(id)",
            queryItems: [URLQueryItem(name: "opt_fields", value: "name,notes,html_notes,completed,completed_at,due_on,due_at,start_on,created_at,modified_at,assignee.name,projects.name,workspace.name,parent.name,permalink_url")],
            accountID: accountID
        )
        return response.data
    }

    // MARK: - Task Mutations

    func createTask(_ task: AsanaTaskCreate, accountID: String) async throws -> AsanaTask {
        let body = try JSONEncoder().encode(["data": task])

        let response: AsanaResponse<AsanaTask> = try await request(
            path: "/tasks",
            method: "POST",
            body: body,
            accountID: accountID
        )
        return response.data
    }

    func completeTask(id: String, accountID: String) async throws -> AsanaTask {
        let body = try JSONSerialization.data(
            withJSONObject: ["data": ["completed": true]],
            options: []
        )

        let response: AsanaResponse<AsanaTask> = try await request(
            path: "/tasks/\(id)",
            method: "PUT",
            body: body,
            accountID: accountID
        )
        return response.data
    }

    func updateTask(id: String, fields: [String: Any], accountID: String) async throws -> AsanaTask {
        let body = try JSONSerialization.data(
            withJSONObject: ["data": fields],
            options: []
        )

        let response: AsanaResponse<AsanaTask> = try await request(
            path: "/tasks/\(id)",
            method: "PUT",
            body: body,
            accountID: accountID
        )
        return response.data
    }

    // MARK: - Stories (Comments)

    func getTaskComments(taskID: String, accountID: String) async throws -> [AsanaStory] {
        let response: AsanaResponse<[AsanaStory]> = try await request(
            path: "/tasks/\(taskID)/stories",
            queryItems: [URLQueryItem(name: "opt_fields", value: "created_at,created_by.name,text,type")],
            accountID: accountID
        )
        return response.data.filter { $0.isComment }
    }

    func addTaskComment(taskID: String, text: String, accountID: String) async throws -> AsanaStory {
        let body = try JSONSerialization.data(
            withJSONObject: ["data": ["text": text]],
            options: []
        )

        let response: AsanaResponse<AsanaStory> = try await request(
            path: "/tasks/\(taskID)/stories",
            method: "POST",
            body: body,
            accountID: accountID
        )
        return response.data
    }

    // MARK: - Projects

    func getProjects(workspaceID: String, accountID: String) async throws -> [AsanaProject] {
        let response: AsanaResponse<[AsanaProject]> = try await request(
            path: "/projects",
            queryItems: [
                URLQueryItem(name: "workspace", value: workspaceID),
                URLQueryItem(name: "opt_fields", value: "name,color,workspace.name"),
                URLQueryItem(name: "archived", value: "false"),
            ],
            accountID: accountID
        )
        return response.data
    }

    // MARK: - Generic Request

    private func request<T: Decodable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        accountID: String,
        retryCount: Int = 0
    ) async throws -> T {
        let token = try await TokenManager.shared.getValidToken(for: accountID)

        var components = URLComponents(string: baseURL + path)!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body {
            request.httpBody = body
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AsanaAPIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                print("Asana decode error: \(error)")
                print("Raw response: \(String(data: data, encoding: .utf8) ?? "nil")")
                throw error
            }

        case 429:
            guard retryCount < maxRetries else {
                throw AsanaAPIError.rateLimited
            }
            let delay = pow(2.0, Double(retryCount + 1))
            try await Task.sleep(for: .seconds(delay))
            return try await self.request(path: path, method: method, queryItems: queryItems, body: body, accountID: accountID, retryCount: retryCount + 1)

        case 401:
            throw AsanaAPIError.unauthorized

        case 403:
            throw AsanaAPIError.forbidden

        case 404:
            throw AsanaAPIError.notFound

        default:
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AsanaAPIError.serverError(httpResponse.statusCode, errorBody)
        }
    }
}

enum AsanaAPIError: LocalizedError {
    case invalidResponse
    case rateLimited
    case unauthorized
    case forbidden
    case notFound
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from Asana."
        case .rateLimited: return "Too many requests to Asana. Please try again later."
        case .unauthorized: return "Not authorized. Please reconnect your Asana account."
        case .forbidden: return "Access denied to this Asana resource."
        case .notFound: return "Asana resource not found."
        case .serverError(let code, let body): return "Asana error (\(code)): \(body)"
        }
    }
}
