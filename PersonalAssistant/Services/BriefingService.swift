import Foundation

@Observable
@MainActor
final class BriefingService {
    private let asana = AsanaAPIClient.shared
    private let granola = GranolaAPIClient.shared
    private let meetingNotes = MeetingNotesReader.shared
    private let claude = ClaudeAPIClient.shared
    private let tokenManager = TokenManager.shared

    func generateBriefing(type: Briefing.BriefingType) async throws -> Briefing {
        var briefing = Briefing(type: type)

        // Fetch data in parallel
        let data = try await fetchBriefingData(type: type)

        // Build sections from raw data
        briefing.sections = buildSections(from: data, type: type)
        briefing.isLoading = false

        // Generate AI summary if Claude is configured
        if let _ = try? tokenManager.getClaudeAPIKey() {
            let summary = try? await generateAISummary(data: data, type: type)
            briefing.aiSummary = summary
        }

        return briefing
    }

    // MARK: - Data Fetching

    private func fetchBriefingData(type: Briefing.BriefingType) async throws -> BriefingData {
        var allTasksDueToday: [AsanaTask] = []
        var allOverdueTasks: [AsanaTask] = []
        var allUpcomingTasks: [AsanaTask] = []
        var allCompletedToday: [AsanaTask] = []
        var workspaces: [AsanaWorkspace] = []

        // Fetch Asana data
        if tokenManager.isAsanaAuthenticated {
            workspaces = try await asana.getWorkspaces()

            for workspace in workspaces {
                async let overdue = asana.getOverdueTasks(workspaceID: workspace.gid)
                async let completed = asana.getTasksCompletedToday(workspaceID: workspace.gid)
                async let myTasks = asana.getMyTasks(workspaceID: workspace.gid, completedSince: Date())

                let overdueResult = (try? await overdue) ?? []
                let completedResult = (try? await completed) ?? []
                let tasksResult = (try? await myTasks) ?? []

                allOverdueTasks.append(contentsOf: overdueResult)
                allCompletedToday.append(contentsOf: completedResult)

                let dueToday = tasksResult.filter { $0.isDueToday }
                allTasksDueToday.append(contentsOf: dueToday)

                let upcoming = tasksResult.filter { task in
                    guard let dueDate = task.dueDate, task.completed != true else { return false }
                    let nextWeek = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
                    return dueDate > Date() && dueDate <= nextWeek && !task.isDueToday
                }
                allUpcomingTasks.append(contentsOf: upcoming)
            }
        }

        // Fetch meeting data (prefer local Obsidian notes, fall back to Granola API)
        var recentMeetings: [GranolaNoteListItem] = []
        var meetingDetails: [GranolaNoteDetail] = []

        let days = type == .morning ? 1 : 1 // Yesterday for morning, today for evening
        if meetingNotes.isConfigured {
            recentMeetings = (try? await meetingNotes.getRecentNotes(days: days)) ?? []
            for meeting in recentMeetings.prefix(3) {
                if let detail = try? await meetingNotes.getNote(id: meeting.id) {
                    meetingDetails.append(detail)
                }
            }
        } else if let _ = try? tokenManager.getGranolaAPIKey() {
            recentMeetings = (try? await granola.getRecentNotes(days: days)) ?? []
            for meeting in recentMeetings.prefix(3) {
                if let detail = try? await granola.getNote(id: meeting.id) {
                    meetingDetails.append(detail)
                }
            }
        }

        return BriefingData(
            tasksDueToday: allTasksDueToday,
            overdueTasks: allOverdueTasks,
            upcomingTasks: allUpcomingTasks,
            completedToday: allCompletedToday,
            recentMeetings: recentMeetings,
            meetingDetails: meetingDetails,
            workspaces: workspaces
        )
    }

    // MARK: - Section Building

    private func buildSections(from data: BriefingData, type: Briefing.BriefingType) -> [BriefingSection] {
        var sections: [BriefingSection] = []

        switch type {
        case .morning:
            // Overdue tasks
            if !data.overdueTasks.isEmpty {
                sections.append(BriefingSection(
                    title: "Overdue",
                    icon: "exclamationmark.triangle.fill",
                    items: data.overdueTasks.map { task in
                        BriefingItem(
                            title: task.name,
                            subtitle: "Due: \(task.dueOn ?? "unknown")",
                            badge: task.workspace.map {
                                BriefingItem.BadgeInfo(text: $0.displayName, color: .red)
                            },
                            urgency: .critical
                        )
                    }
                ))
            }

            // Due today
            if !data.tasksDueToday.isEmpty {
                sections.append(BriefingSection(
                    title: "Due Today",
                    icon: "calendar.badge.exclamationmark",
                    items: data.tasksDueToday.map { task in
                        BriefingItem(
                            title: task.name,
                            subtitle: task.projects?.first?.name,
                            badge: task.workspace.map {
                                BriefingItem.BadgeInfo(text: $0.displayName, color: .blue)
                            },
                            urgency: .warning
                        )
                    }
                ))
            }

            // Today's meetings
            if !data.recentMeetings.isEmpty {
                sections.append(BriefingSection(
                    title: "Recent Meetings",
                    icon: "person.2.fill",
                    items: data.recentMeetings.prefix(5).map { meeting in
                        BriefingItem(
                            title: meeting.displayTitle,
                            subtitle: nil,
                            badge: BriefingItem.BadgeInfo(text: "Meeting", color: .purple)
                        )
                    }
                ))
            }

            // Upcoming this week
            if !data.upcomingTasks.isEmpty {
                sections.append(BriefingSection(
                    title: "Coming This Week",
                    icon: "calendar",
                    items: data.upcomingTasks.prefix(5).map { task in
                        BriefingItem(
                            title: task.name,
                            subtitle: task.dueDate.map { DateFormatting.shortDate($0) }
                        )
                    }
                ))
            }

        case .evening:
            // Completed today
            if !data.completedToday.isEmpty {
                sections.append(BriefingSection(
                    title: "Completed Today",
                    icon: "checkmark.circle.fill",
                    items: data.completedToday.map { task in
                        BriefingItem(
                            title: task.name,
                            badge: task.workspace.map {
                                BriefingItem.BadgeInfo(text: $0.displayName, color: .green)
                            }
                        )
                    }
                ))
            }

            // Still open from today
            let stillOpen = data.tasksDueToday.filter { $0.completed != true }
            if !stillOpen.isEmpty {
                sections.append(BriefingSection(
                    title: "Still Open",
                    icon: "circle",
                    items: stillOpen.map { task in
                        BriefingItem(
                            title: task.name,
                            subtitle: "Was due today",
                            urgency: .warning
                        )
                    }
                ))
            }

            // Meetings attended
            if !data.meetingDetails.isEmpty {
                sections.append(BriefingSection(
                    title: "Today's Meetings",
                    icon: "person.2.fill",
                    items: data.meetingDetails.map { meeting in
                        BriefingItem(
                            title: meeting.displayTitle,
                            subtitle: meeting.summaryText?.prefix(100).description
                        )
                    }
                ))
            }
        }

        // Add empty state if nothing
        if sections.isEmpty {
            sections.append(BriefingSection(
                title: type == .morning ? "All Clear" : "Quiet Day",
                icon: "sun.max.fill",
                items: [BriefingItem(
                    title: type == .morning ? "No tasks or meetings found for today." : "No activity recorded today.",
                    subtitle: "Connect your accounts in Settings to see your data here."
                )]
            ))
        }

        return sections
    }

    // MARK: - AI Summary

    private func generateAISummary(data: BriefingData, type: Briefing.BriefingType) async throws -> String {
        let prompt: String
        switch type {
        case .morning:
            prompt = """
            Generate a brief, friendly morning briefing summary (2-3 short paragraphs).
            Highlight the most important things to focus on today.
            If there are overdue tasks, mention them with urgency.
            Suggest priorities based on due dates and meeting action items.
            Keep it concise and actionable.
            """
        case .evening:
            prompt = """
            Generate a brief evening recap (2-3 short paragraphs).
            Celebrate completed work.
            Note any tasks that were due today but not completed.
            Summarize meeting outcomes and action items.
            Suggest follow-ups for tomorrow.
            Keep it encouraging and constructive.
            """
        }

        let messages = [ClaudeMessage(role: "user", content: .text(prompt))]
        let systemPrompt = "You are a personal assistant generating a \(type == .morning ? "morning" : "evening") briefing. Be concise, helpful, and actionable.\n\nDATA:\n\(data.contextForClaude)"

        return try await claude.sendMessage(
            messages: messages,
            systemPrompt: systemPrompt
        )
    }
}
