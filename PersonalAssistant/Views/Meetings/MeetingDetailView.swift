import SwiftUI

struct MeetingDetailView: View {
    let meetingID: String

    @State private var detail: GranolaNoteDetail?
    @State private var isLoading = true
    @State private var error: String?

    // AI Summary
    @State private var aiSummary: String?
    @State private var actionItems: [String] = []
    @State private var isGeneratingSummary = false
    @State private var summaryError: String?

    private let granola = GranolaAPIClient.shared
    private let meetingNotes = MeetingNotesReader.shared
    private let claude = ClaudeAPIClient.shared
    private let tokenManager = TokenManager.shared

    var body: some View {
        Group {
            if isLoading {
                LoadingIndicator("Loading meeting...")
            } else if let error {
                ErrorStateView(error) {
                    Task { await loadDetail() }
                }
            } else if let detail {
                meetingContent(detail)
            }
        }
        .navigationTitle("Meeting Details")
        .inlineNavigationBarTitle()
        .task {
            await loadDetail()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func meetingContent(_ detail: GranolaNoteDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(detail.displayTitle)
                        .font(.title3)
                        .fontWeight(.semibold)

                    if detail.id.hasPrefix("local-") {
                        WorkspaceBadge(text: "Local Notes", color: .teal)
                    } else {
                        WorkspaceBadge(text: "Granola", color: .purple)
                    }
                }

                Divider()

                // Metadata
                VStack(alignment: .leading, spacing: 12) {
                    if let date = parseDate(detail.createdAt) {
                        MetadataRow(icon: "calendar", label: "Date", value: DateFormatting.fullDate(date))
                    }

                    if let event = detail.calendarEvent,
                       let start = event.scheduledStartTime,
                       let startDate = parseDate(start) {
                        let endText = event.scheduledEndTime
                            .flatMap { parseDate($0) }
                            .map { " – \(DateFormatting.time($0))" } ?? ""
                        MetadataRow(icon: "clock", label: "Time", value: DateFormatting.time(startDate) + endText)
                    }

                    if let attendees = detail.attendees, !attendees.isEmpty {
                        MetadataRow(icon: "person.2", label: "Attendees", value: "\(attendees.count) people")
                    }
                }

                // Attendees
                if let attendees = detail.attendees, !attendees.isEmpty {
                    Divider()
                    attendeesSection(attendees)
                }

                // AI Summary
                Divider()
                aiSummarySection(detail)

                // Meeting Notes
                if let markdown = detail.summaryMarkdown, !markdown.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Meeting Notes")
                            .font(.headline)
                        MarkdownTextView(text: markdown)
                            .font(.body)
                    }
                } else if let text = detail.summaryText, !text.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Meeting Notes")
                            .font(.headline)
                        Text(text)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }

                // Transcript
                if let transcript = detail.transcript, !transcript.isEmpty {
                    Divider()
                    transcriptSection(transcript)
                }

                Spacer(minLength: 40)
            }
            .padding()
        }
    }

    // MARK: - Attendees

    @ViewBuilder
    private func attendeesSection(_ attendees: [GranolaAttendee]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Attendees")
                .font(.headline)

            ForEach(attendees.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    Image(systemName: "person.circle.fill")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(attendees[index].displayName)
                            .font(.subheadline)
                        if let email = attendees[index].email, attendees[index].name != nil {
                            Text(email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - AI Summary

    @ViewBuilder
    private func aiSummarySection(_ detail: GranolaNoteDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("AI Summary", systemImage: "sparkles")
                .font(.headline)

            if let summary = aiSummary {
                VStack(alignment: .leading, spacing: 12) {
                    MarkdownTextView(text: summary)
                        .font(.subheadline)

                    if !actionItems.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Action Items")
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            ForEach(actionItems.indices, id: \.self) { index in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "circle")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 3)
                                    Text(actionItems[index])
                                        .font(.subheadline)
                                }
                            }
                        }
                    }

                    Button {
                        Task { await generateSummary(detail) }
                    } label: {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.accentColor.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                )
            } else if isGeneratingSummary {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Generating summary...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.systemGray6Color)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if let summaryError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(summaryError)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Button("Try Again") {
                        Task { await generateSummary(detail) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                let hasContent = (detail.summaryText != nil && detail.summaryText?.isEmpty == false)
                    || (detail.summaryMarkdown != nil && detail.summaryMarkdown?.isEmpty == false)
                    || (detail.transcript != nil && detail.transcript?.isEmpty == false)
                let hasClaudeKey = ((try? tokenManager.getClaudeAPIKey()) != nil)

                if hasContent && hasClaudeKey {
                    Button {
                        Task { await generateSummary(detail) }
                    } label: {
                        Label("Generate Summary", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else if !hasClaudeKey {
                    Text("Add your Claude API key in Settings to generate AI summaries.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No meeting content available to summarize.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Transcript

    @ViewBuilder
    private func transcriptSection(_ segments: [GranolaTranscriptSegment]) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(segments.prefix(200).indices, id: \.self) { index in
                    let segment = segments[index]
                    VStack(alignment: .leading, spacing: 2) {
                        if let speaker = segment.speaker?.source {
                            Text(speaker)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                        }
                        Text(segment.text)
                            .font(.caption)
                    }
                    .padding(.vertical, 2)
                }
            }
        } label: {
            Text("Transcript")
                .font(.headline)
        }
    }

    // MARK: - Data Loading

    private func loadDetail() async {
        isLoading = true
        error = nil

        do {
            if meetingNotes.isConfigured {
                detail = try await meetingNotes.getNote(id: meetingID)
            } else {
                detail = try await granola.getNoteWithTranscript(id: meetingID)
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - AI Summary

    private func generateSummary(_ detail: GranolaNoteDetail) async {
        isGeneratingSummary = true
        summaryError = nil

        var content = ""
        if let markdown = detail.summaryMarkdown, !markdown.isEmpty {
            content = markdown
        } else if let text = detail.summaryText, !text.isEmpty {
            content = text
        }

        if let transcript = detail.transcript, !transcript.isEmpty {
            let transcriptText = transcript
                .map { segment in
                    let speaker = segment.speaker?.source ?? "Speaker"
                    return "\(speaker): \(segment.text)"
                }
                .joined(separator: "\n")
            if content.isEmpty {
                content = transcriptText
            } else {
                content += "\n\nTRANSCRIPT:\n" + transcriptText
            }
        }

        guard !content.isEmpty else {
            summaryError = "No meeting content available to summarize."
            isGeneratingSummary = false
            return
        }

        let truncated = String(content.prefix(12000))

        let systemPrompt = """
        You are summarizing a meeting. Provide:
        1. A concise summary (2-3 paragraphs) of what was discussed and any decisions made.
        2. A list of action items, each on its own line prefixed with "ACTION: ".

        Be concise and focus on outcomes, decisions, and next steps.
        """

        let userMessage = "Summarize this meeting titled \"\(detail.displayTitle)\":\n\n\(truncated)"

        do {
            let messages = [ClaudeMessage(role: "user", content: .text(userMessage))]
            let response = try await claude.sendMessage(messages: messages, systemPrompt: systemPrompt)

            let lines = response.components(separatedBy: "\n")
            var summaryLines: [String] = []
            var extractedActions: [String] = []

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("ACTION: ") {
                    extractedActions.append(String(trimmed.dropFirst("ACTION: ".count)))
                } else {
                    summaryLines.append(line)
                }
            }

            aiSummary = summaryLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            actionItems = extractedActions
        } catch {
            summaryError = error.localizedDescription
        }

        isGeneratingSummary = false
    }

    // MARK: - Helpers

    private func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
