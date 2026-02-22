import Foundation

struct Briefing: Identifiable {
    let id: UUID
    let type: BriefingType
    let generatedAt: Date
    var sections: [BriefingSection]
    var aiSummary: String?
    var aiSummaryCards: [BriefingSummaryCard]
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
        aiSummaryCards: [BriefingSummaryCard] = [],
        isLoading: Bool = true
    ) {
        self.id = id
        self.type = type
        self.generatedAt = generatedAt
        self.sections = sections
        self.aiSummary = aiSummary
        self.aiSummaryCards = aiSummaryCards
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
    let taskGID: String?
    let emoji: String?

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
        urgency: Urgency = .normal,
        taskGID: String? = nil,
        emoji: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.badge = badge
        self.urgency = urgency
        self.taskGID = taskGID
        self.emoji = emoji
    }
}

// MARK: - AI Summary Cards

struct BriefingSummaryCard: Identifiable {
    let id: UUID
    let category: Category
    let content: String

    enum Category: String, CaseIterable {
        case priorities = "Priorities"
        case overdue = "Overdue Alert"
        case meetings = "Meeting Insights"
        case actions = "Action Items"
        case progress = "Progress"
        case upcoming = "Looking Ahead"
        case general = "Summary"

        var icon: String {
            switch self {
            case .priorities: return "star.fill"
            case .overdue: return "exclamationmark.triangle.fill"
            case .meetings: return "person.2.fill"
            case .actions: return "checklist"
            case .progress: return "chart.bar.fill"
            case .upcoming: return "calendar"
            case .general: return "sparkles"
            }
        }

        var accentColor: Color {
            switch self {
            case .priorities: return AppTheme.accent
            case .overdue: return AppTheme.urgencyRed
            case .meetings: return AppTheme.badgeGranola
            case .actions: return AppTheme.urgencyOrange
            case .progress: return AppTheme.urgencyGreen
            case .upcoming: return .blue
            case .general: return AppTheme.accent
            }
        }
    }

    init(id: UUID = UUID(), category: Category, content: String) {
        self.id = id
        self.category = category
        self.content = content
    }

    /// Parse a structured AI response (sections delimited by "### HEADING") into cards
    static func parse(from text: String) -> [BriefingSummaryCard] {
        let lines = text.components(separatedBy: "\n")
        var cards: [BriefingSummaryCard] = []
        var currentCategory: Category?
        var currentLines: [String] = []

        let categoryMap: [String: Category] = [
            "priorities": .priorities,
            "priority": .priorities,
            "focus": .priorities,
            "overdue": .overdue,
            "overdue alert": .overdue,
            "urgent": .overdue,
            "meetings": .meetings,
            "meeting insights": .meetings,
            "meeting": .meetings,
            "action items": .actions,
            "actions": .actions,
            "next steps": .actions,
            "progress": .progress,
            "completed": .progress,
            "accomplishments": .progress,
            "looking ahead": .upcoming,
            "upcoming": .upcoming,
            "tomorrow": .upcoming,
            "summary": .general,
        ]

        func flush() {
            let content = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty, let cat = currentCategory {
                cards.append(BriefingSummaryCard(category: cat, content: content))
            }
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("### ") {
                flush()
                let heading = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces).lowercased()
                currentCategory = categoryMap[heading] ?? .general
                currentLines = []
            } else {
                if currentCategory == nil && !trimmed.isEmpty {
                    // Content before any heading — treat as general
                    currentCategory = .general
                }
                currentLines.append(line)
            }
        }
        flush()

        return cards
    }
}

import SwiftUI

// MARK: - Raw Briefing Data (pre-AI processing)

struct BriefingData {
    let tasksDueToday: [AsanaTask]
    let overdueTasks: [AsanaTask]
    let upcomingTasks: [AsanaTask]
    let completedToday: [AsanaTask]
    let calendarEvents: [CalendarMeetingItem]
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

        if !calendarEvents.isEmpty {
            context += "TODAY'S CALENDAR (\(calendarEvents.count) events):\n"
            for event in calendarEvents {
                let timeStr = event.isAllDay ? "All Day" : DateFormatting.time(event.startDate) + " – " + DateFormatting.time(event.endDate)
                context += "- \(event.title) (\(timeStr))"
                if event.hasGranolaNote { context += " [has notes]" }
                context += "\n"
            }
            context += "\n"
        }

        if !meetingDetails.isEmpty {
            context += "MEETING NOTES:\n"
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
