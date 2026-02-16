import Foundation

final class ClaudeAPIClient: Sendable {
    static let shared = ClaudeAPIClient()

    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let apiVersion = "2023-06-01"

    enum Model: String, Sendable {
        case haiku = "claude-haiku-4-5-20251001"
        case sonnet = "claude-sonnet-4-5-20250929"
    }

    private init() {}

    // MARK: - Tool Definitions

    static let tools: [[String: Any]] = [
        [
            "name": "create_asana_task",
            "description": "Create a new task in Asana. Use this when the user asks to create a task, add a to-do, or set a reminder.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "The task name/title"],
                    "notes": ["type": "string", "description": "Task description or notes"],
                    "due_on": ["type": "string", "description": "Due date in YYYY-MM-DD format"],
                    "project_name": ["type": "string", "description": "Project name to add the task to (optional)"],
                    "workspace_name": ["type": "string", "description": "Workspace name (optional, defaults to first workspace)"],
                ],
                "required": ["name"],
            ] as [String: Any],
        ],
        [
            "name": "complete_asana_task",
            "description": "Mark an Asana task as complete. Use this when the user says they finished a task.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "task_id": ["type": "string", "description": "The Asana task GID to complete"],
                ],
                "required": ["task_id"],
            ] as [String: Any],
        ],
        [
            "name": "get_tasks_due",
            "description": "Get tasks due in a date range. Use this when the user asks about upcoming tasks.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "date_range": ["type": "string", "enum": ["today", "this_week", "overdue"], "description": "The date range to query"],
                ],
                "required": ["date_range"],
            ] as [String: Any],
        ],
        [
            "name": "search_meeting_notes",
            "description": "Search through recent meeting notes from Granola. Use this when the user asks about meetings or what was discussed.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Search query for meeting notes"],
                ],
                "required": ["query"],
            ] as [String: Any],
        ],
        [
            "name": "update_asana_task",
            "description": "Update an existing Asana task. Use this when the user asks to change a due date, rename a task, or update task notes.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "task_id": ["type": "string", "description": "The Asana task GID to update"],
                    "due_on": ["type": "string", "description": "New due date in YYYY-MM-DD format"],
                    "name": ["type": "string", "description": "New task name"],
                    "notes": ["type": "string", "description": "New task notes/description"],
                ],
                "required": ["task_id"],
            ] as [String: Any],
        ],
        [
            "name": "get_task_comments",
            "description": "Get comments on an Asana task. Use this when the user asks about comments or discussion on a task.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "task_id": ["type": "string", "description": "The Asana task GID to get comments for"],
                ],
                "required": ["task_id"],
            ] as [String: Any],
        ],
        [
            "name": "add_task_comment",
            "description": "Add a comment to an Asana task. Use this when the user asks to leave a comment or note on a task.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "task_id": ["type": "string", "description": "The Asana task GID to comment on"],
                    "text": ["type": "string", "description": "The comment text to post"],
                ],
                "required": ["task_id", "text"],
            ] as [String: Any],
        ],
    ]

    // MARK: - Streaming Messages

    func streamMessage(
        messages: [ClaudeMessage],
        systemPrompt: String,
        model: Model = .haiku,
        tools: [[String: Any]]? = nil,
        onText: @escaping @Sendable (String) -> Void,
        onToolUse: @escaping @Sendable (String, String, [String: Any]) -> Void,
        onComplete: @escaping @Sendable (StopReason) -> Void
    ) async throws {
        guard let apiKey = try TokenManager.shared.getClaudeAPIKey(), !apiKey.isEmpty else {
            throw ClaudeAPIError.noAPIKey
        }

        var requestBody: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 4096,
            "system": systemPrompt,
            "stream": true,
        ]

        let encodedMessages = try messages.map { msg -> [String: Any] in
            let encoder = JSONEncoder()
            let data = try encoder.encode(msg)
            return try JSONSerialization.jsonObject(with: data) as! [String: Any]
        }
        requestBody["messages"] = encodedMessages

        if let tools {
            requestBody["tools"] = tools
        }

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
            }
            let errorBody = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw ClaudeAPIError.serverError(httpResponse.statusCode, errorBody)
        }

        // Parse SSE stream
        var currentToolID: String?
        var currentToolName: String?
        var toolInputJSON = ""

        for try await line in bytes.lines {
            if line.hasPrefix("event: ") {
                continue
            }

            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))

            guard let jsonData = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            else { continue }

            let eventType = json["type"] as? String

            switch eventType {
            case "content_block_start":
                if let contentBlock = json["content_block"] as? [String: Any],
                   contentBlock["type"] as? String == "tool_use" {
                    currentToolID = contentBlock["id"] as? String
                    currentToolName = contentBlock["name"] as? String
                    toolInputJSON = ""
                }

            case "content_block_delta":
                if let delta = json["delta"] as? [String: Any] {
                    let deltaType = delta["type"] as? String

                    if deltaType == "text_delta", let text = delta["text"] as? String {
                        onText(text)
                    } else if deltaType == "input_json_delta", let partial = delta["partial_json"] as? String {
                        toolInputJSON += partial
                    }
                }

            case "content_block_stop":
                if let toolID = currentToolID, let toolName = currentToolName {
                    let input: [String: Any]
                    if let data = toolInputJSON.data(using: .utf8),
                       let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        input = parsed
                    } else {
                        input = [:]
                    }
                    onToolUse(toolID, toolName, input)
                    currentToolID = nil
                    currentToolName = nil
                    toolInputJSON = ""
                }

            case "message_delta":
                if let delta = json["delta"] as? [String: Any],
                   let stopReason = delta["stop_reason"] as? String {
                    onComplete(StopReason(rawValue: stopReason) ?? .endTurn)
                }

            default:
                break
            }
        }
    }

    // MARK: - Non-streaming (for briefings)

    func sendMessage(
        messages: [ClaudeMessage],
        systemPrompt: String,
        model: Model = .haiku
    ) async throws -> String {
        guard let apiKey = try TokenManager.shared.getClaudeAPIKey(), !apiKey.isEmpty else {
            throw ClaudeAPIError.noAPIKey
        }

        let encodedMessages = try messages.map { msg -> [String: Any] in
            let encoder = JSONEncoder()
            let data = try encoder.encode(msg)
            return try JSONSerialization.jsonObject(with: data) as! [String: Any]
        }

        let requestBody: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": encodedMessages,
        ]

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ClaudeAPIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0, errorBody)
        }

        let result = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let content = result?["content"] as? [[String: Any]],
           let firstBlock = content.first,
           firstBlock["type"] as? String == "text",
           let text = firstBlock["text"] as? String {
            return text
        }

        throw ClaudeAPIError.noContent
    }

    // MARK: - Types

    enum StopReason: String, Sendable {
        case endTurn = "end_turn"
        case toolUse = "tool_use"
        case maxTokens = "max_tokens"
        case stopSequence = "stop_sequence"
    }
}

enum ClaudeAPIError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case noContent
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No Claude API key configured. Add your key in Settings."
        case .invalidResponse: return "Invalid response from Claude API."
        case .noContent: return "No content in Claude API response."
        case .serverError(let code, let body): return "Claude API error (\(code)): \(body)"
        }
    }
}
