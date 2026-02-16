import Foundation

struct Briefing: Identifiable {
    let id: UUID
    let type: BriefingType
    let generatedAt: Date
    var sections: [BriefingSection]
    var aiSummary: String?
    var isLoading: Bool

    enum BriefingType {
        case morning
        case evening

        var title: String {
            switch self {
            case .morning: return "Good Morning"
            case .evening: return "Evening Recap"
            }
        }

        var subtitle: String {
            switch self {
            case .morning: return "Here's your day ahead"
            case .evening: return "Here's how your day went"
            }
        }
    }

    init(
        id: UUID = UUID(),
        type: BriefingType,
        generatedAt: Date = Date(),
        sections: [BriefingSection] = [],
        aiSummary: String? = nil,
        isLoading: Bool = true
    ) {
        self.id = id
        self.type = type
        self.generatedAt = generatedAt
        self.sections = sections
        self.aiSummary = aiSummary
        self.isLoading = isLoading
    }
}

struct BriefingSection: Identifiable {
    let id: UUID
    let title: String
    let icon: String
    let items: [BriefingItem]

    init(id: UUID = UUID(), title: String, icon: String, items: [BriefingItem]) {
        self.id = id
        self.title = title
        self.icon = icon
        self.items = items
    }
}

struct BriefingItem: Identifiable {
    let id: UUID
    let title: String
    let subtitle: String?
    let badge: BadgeInfo?
    let urgency: Urgency

    enum Urgency {
        case normal
        case warning
        case critical
    }

    struct BadgeInfo {
        let text: String
        let color: BadgeColor

        enum BadgeColor {
            case blue, green, orange, red, purple, gray
        }
    }

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String? = nil,
        badge: BadgeInfo? = nil,
        urgency: Urgency = .normal
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.badge = badge
        self.urgency = urgency
    }
}

// MARK: - Raw Briefing Data (pre-AI processing)

struct BriefingData {
    let tasksDueToday: [AsanaTask]
    let overdueTasks: [AsanaTask]
    let upcomingTasks: [AsanaTask]
    let completedToday: [AsanaTask]
    let recentMeetings: [GranolaNoteListItem]
    let meetingDetails: [GranolaNoteDetail]
    let workspaces: [AsanaWorkspace]

    var contextForClaude: String {
        var context = "Current date: \(DateFormatting.fullDate(Date()))\n\n"

        if !overdueTasks.isEmpty {
            context += "OVERDUE TASKS (\(overdueTasks.count)):\n"
            for task in overdueTasks {
                context += "- \(task.name) (due: \(task.dueOn ?? "unknown"))\n"
            }
            context += "\n"
        }

        if !tasksDueToday.isEmpty {
            context += "DUE TODAY (\(tasksDueToday.count)):\n"
            for task in tasksDueToday {
                let project = task.projects?.first?.name ?? "No project"
                context += "- \(task.name) [\(project)]\n"
            }
            context += "\n"
        }

        if !upcomingTasks.isEmpty {
            context += "UPCOMING TASKS (next 7 days, \(upcomingTasks.count)):\n"
            for task in upcomingTasks.prefix(10) {
                context += "- \(task.name) (due: \(task.dueOn ?? "unknown"))\n"
            }
            context += "\n"
        }

        if !completedToday.isEmpty {
            context += "COMPLETED TODAY (\(completedToday.count)):\n"
            for task in completedToday {
                context += "- \(task.name)\n"
            }
            context += "\n"
        }

        if !meetingDetails.isEmpty {
            context += "RECENT MEETINGS:\n"
            for meeting in meetingDetails {
                context += "- \(meeting.displayTitle)"
                if let summary = meeting.summaryText {
                    context += ": \(summary.prefix(200))"
                }
                context += "\n"
            }
        }

        return context
    }
}
