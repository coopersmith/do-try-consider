import Foundation

@Observable
@MainActor
final class BriefingService {
    private let asana = AsanaAPIClient.shared
    private let granola = GranolaAPIClient.shared
    private let meetingNotes = MeetingNotesReader.shared
    private let claude = ClaudeAPIClient.shared
    private let tokenManager = TokenManager.shared
    private let calendarService = CalendarService.shared
    private let noteMatching = NoteMatchingService.shared

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
            if let summary {
                briefing.aiSummaryCards = BriefingSummaryCard.parse(from: summary)
            }
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

        // Fetch calendar events for today
        var calendarEvents: [CalendarMeetingItem] = []
        var meetingDetails: [GranolaNoteDetail] = []

        let todayStart = Calendar.current.startOfDay(for: Date())
        let todayEnd = Calendar.current.date(byAdding: .day, value: 1, to: todayStart)!

        if calendarService.permissionStatus == .authorized {
            calendarEvents = calendarService.fetchEvents(from: todayStart, to: todayEnd)
            calendarEvents = await noteMatching.matchNotes(to: calendarEvents)

            // Fetch Granola details for matched events (for AI context)
            for event in calendarEvents where event.hasGranolaNote {
                if let noteID = event.granolaNoteID,
                   let detail = try? await granola.getNote(id: noteID) {
                    meetingDetails.append(detail)
                }
            }
        }

        return BriefingData(
            tasksDueToday: allTasksDueToday,
            overdueTasks: allOverdueTasks,
            upcomingTasks: allUpcomingTasks,
            completedToday: allCompletedToday,
            calendarEvents: calendarEvents,
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

            // Today's meetings (from calendar)
            if !data.calendarEvents.isEmpty {
                sections.append(BriefingSection(
                    title: "Today's Meetings",
                    icon: "calendar",
                    items: data.calendarEvents.prefix(5).map { event in
                        let timeText = event.isAllDay ? "All Day" : DateFormatting.time(event.startDate)
                        return BriefingItem(
                            title: event.title,
                            subtitle: timeText,
                            badge: BriefingItem.BadgeInfo(text: "Calendar", color: .blue)
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

            // Meetings attended (from calendar)
            if !data.calendarEvents.isEmpty {
                sections.append(BriefingSection(
                    title: "Today's Meetings",
                    icon: "calendar",
                    items: data.calendarEvents.map { event in
                        let timeText = event.isAllDay ? "All Day" : DateFormatting.time(event.startDate)
                        let noteSuffix = event.hasGranolaNote ? " (has notes)" : ""
                        return BriefingItem(
                            title: event.title,
                            subtitle: timeText + noteSuffix
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
            Generate a morning briefing organized into categories. Use EXACTLY these markdown headings (include only categories that have relevant content):

            ### Priorities
            Top 2-3 things to focus on today (1-2 sentences each).

            ### Overdue Alert
            Only if there are overdue tasks. Be direct about what needs attention.

            ### Meeting Insights
            Only if there are recent meetings. Key takeaways or prep notes.

            ### Action Items
            Bullet list of concrete next steps from tasks and meetings.

            Keep each section to 2-4 sentences or bullets. Be concise and actionable.
            """
        case .evening:
            prompt = """
            Generate an evening recap organized into categories. Use EXACTLY these markdown headings (include only categories that have relevant content):

            ### Progress
            Celebrate completed work. What was accomplished today.

            ### Overdue Alert
            Only if tasks were due today but not completed. Be constructive, not harsh.

            ### Meeting Insights
            Only if there were meetings. Key outcomes and decisions.

            ### Action Items
            Bullet list of follow-ups for tomorrow.

            ### Looking Ahead
            Brief note on what's coming tomorrow/this week.

            Keep each section to 2-4 sentences or bullets. Be encouraging and constructive.
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
