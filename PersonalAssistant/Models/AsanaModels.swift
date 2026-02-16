import Foundation

// MARK: - API Response Wrapper

struct AsanaResponse<T: Codable>: Codable {
    let data: T
    let nextPage: AsanaNextPage?

    enum CodingKeys: String, CodingKey {
        case data
        case nextPage = "next_page"
    }
}

struct AsanaNextPage: Codable {
    let offset: String?
    let path: String?
    let uri: String?
}

// MARK: - Workspace

struct AsanaWorkspace: Codable, Identifiable, Hashable {
    let gid: String
    let name: String?
    let isOrganization: Bool?

    var id: String { gid }
    var displayName: String { name ?? "Workspace" }

    enum CodingKeys: String, CodingKey {
        case gid, name
        case isOrganization = "is_organization"
    }
}

// MARK: - User

struct AsanaUser: Codable, Identifiable {
    let gid: String
    let name: String
    let email: String?
    let photo: AsanaPhoto?
    let workspaces: [AsanaWorkspace]?

    var id: String { gid }
}

struct AsanaPhoto: Codable {
    let image21x21: String?
    let image27x27: String?
    let image36x36: String?
    let image60x60: String?
    let image128x128: String?

    enum CodingKeys: String, CodingKey {
        case image21x21 = "image_21x21"
        case image27x27 = "image_27x27"
        case image36x36 = "image_36x36"
        case image60x60 = "image_60x60"
        case image128x128 = "image_128x128"
    }
}

// MARK: - Project

struct AsanaProject: Codable, Identifiable, Hashable {
    let gid: String
    let name: String?
    let color: String?
    let workspace: AsanaWorkspace?

    var id: String { gid }

    func hash(into hasher: inout Hasher) {
        hasher.combine(gid)
    }

    static func == (lhs: AsanaProject, rhs: AsanaProject) -> Bool {
        lhs.gid == rhs.gid
    }
}

// MARK: - Task

struct AsanaTask: Codable, Identifiable {
    let gid: String
    let name: String
    let notes: String?
    let htmlNotes: String?
    let completed: Bool?
    let completedAt: String?
    let dueOn: String?
    let dueAt: String?
    let startOn: String?
    let createdAt: String?
    let modifiedAt: String?
    let assignee: AsanaUser?
    let projects: [AsanaProject]?
    let workspace: AsanaWorkspace?
    let parent: AsanaTaskRef?
    let permalink: String?

    var id: String { gid }

    var dueDate: Date? {
        guard let dueOn else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dueOn)
    }

    var isOverdue: Bool {
        guard let dueDate, completed != true else { return false }
        return dueDate < Calendar.current.startOfDay(for: Date())
    }

    var isDueToday: Bool {
        guard let dueDate else { return false }
        return Calendar.current.isDateInToday(dueDate)
    }

    enum CodingKeys: String, CodingKey {
        case gid, name, notes, completed, assignee, projects, workspace, parent
        case htmlNotes = "html_notes"
        case completedAt = "completed_at"
        case dueOn = "due_on"
        case dueAt = "due_at"
        case startOn = "start_on"
        case createdAt = "created_at"
        case modifiedAt = "modified_at"
        case permalink = "permalink_url"
    }
}

struct AsanaTaskRef: Codable {
    let gid: String
    let name: String?
}

// MARK: - Story (Comment)

struct AsanaStory: Codable, Identifiable {
    let gid: String
    let createdAt: String?
    let createdBy: AsanaUser?
    let text: String?
    let type: String?

    var id: String { gid }

    var isComment: Bool {
        type == "comment"
    }

    var createdDate: Date? {
        guard let createdAt else { return nil }
        return DateFormatting.dateFromISO(createdAt)
    }

    enum CodingKeys: String, CodingKey {
        case gid, text, type
        case createdAt = "created_at"
        case createdBy = "created_by"
    }
}

// MARK: - Task Creation

struct AsanaTaskCreate: Codable {
    let name: String
    let notes: String?
    let dueOn: String?
    let projects: [String]?
    let workspace: String
    let assignee: String?

    enum CodingKeys: String, CodingKey {
        case name, notes, projects, workspace, assignee
        case dueOn = "due_on"
    }
}

// MARK: - OAuth Token Response

struct AsanaTokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let tokenType: String
    let expiresIn: Int
    let data: AsanaUser?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case data
    }
}
