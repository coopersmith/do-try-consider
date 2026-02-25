import SwiftUI

struct CalendarEventDetailView: View {
    let meeting: CalendarMeetingItem

    @State private var noteDetail: GranolaNoteDetail?
    @State private var isLoadingNote = false
    @State private var noteError: String?
    @State private var showConvertSheet = false

    private let granola = GranolaAPIClient.shared
    private let meetingNotes = MeetingNotesReader.shared
    private let tokenManager = TokenManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(meeting.title)
                        .font(AppTheme.title3Font)

                    HStack(spacing: 6) {
                        WorkspaceBadge(
                            text: meeting.calendarName,
                            color: Color(hex: meeting.calendarColorHex)
                        )
                        if meeting.hasGranolaNote {
                            WorkspaceBadge(text: "Notes", color: AppTheme.badgeGranola)
                        }
                    }
                }

                Divider()

                // Metadata
                WarmCard {
                    VStack(alignment: .leading, spacing: 12) {
                        MetadataRow(
                            icon: "calendar",
                            label: "Date",
                            value: DateFormatting.fullDate(meeting.startDate)
                        )

                        if meeting.isAllDay {
                            MetadataRow(icon: "clock", label: "Time", value: "All Day")
                        } else {
                            MetadataRow(
                                icon: "clock",
                                label: "Time",
                                value: "\(DateFormatting.time(meeting.startDate)) – \(DateFormatting.time(meeting.endDate))"
                            )
                        }

                        if let location = meeting.location, !location.isEmpty {
                            MetadataRow(icon: "mappin.and.ellipse", label: "Location", value: location)
                        }

                        if !meeting.attendees.isEmpty {
                            MetadataRow(
                                icon: "person.2",
                                label: "Attendees",
                                value: "\(meeting.attendees.count) people"
                            )
                        }
                    }
                }

                // Attendees
                if !meeting.attendees.isEmpty {
                    attendeesSection
                }

                // Calendar Event Notes
                if let notes = meeting.notes, !notes.isEmpty,
                   let cleaned = Self.stripVideoConferenceCruft(notes), !cleaned.isEmpty {
                    WarmCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Event Notes")
                                .font(AppTheme.sectionHeaderFont)
                            MarkdownTextView(text: cleaned)
                                .font(AppTheme.bodyFont)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }

                // Granola Meeting Notes
                if meeting.hasGranolaNote {
                    granolaNotesSection
                }

                Spacer(minLength: 40)
            }
            .padding()
        }
        .warmScrollBackground()
        .background(AppTheme.adaptiveBackground)
        .navigationTitle("Event Details")
        .inlineNavigationBarTitle()
        .task {
            if meeting.hasGranolaNote {
                await loadGranolaNote()
            }
        }
        .sheet(isPresented: $showConvertSheet) {
            if let noteDetail {
                ConvertToTasksSheet(
                    meetingTitle: meeting.title,
                    noteContent: noteDetail.summaryMarkdown ?? noteDetail.summaryText ?? ""
                )
            }
        }
    }

    // MARK: - Attendees

    private var attendeesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Attendees")
                .font(AppTheme.sectionHeaderFont)

            ForEach(meeting.attendees.indices, id: \.self) { index in
                let attendee = meeting.attendees[index]
                HStack(spacing: 8) {
                    Image(systemName: attendee.isOrganizer ? "person.circle.fill" : "person.circle")
                        .foregroundStyle(attendee.isOrganizer ? AppTheme.accent : AppTheme.textSecondary)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(attendee.displayName)
                                .font(AppTheme.subheadlineFont)
                            if attendee.isOrganizer {
                                Text("Organizer")
                                    .font(AppTheme.caption2Font)
                                    .foregroundStyle(AppTheme.accent)
                            }
                        }
                        if let email = attendee.email, attendee.name != nil {
                            Text(email)
                                .font(AppTheme.captionFont)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Granola Notes

    @ViewBuilder
    private var granolaNotesSection: some View {
        if isLoadingNote {
            WarmCard {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading meeting notes...")
                        .font(AppTheme.subheadlineFont)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if let noteError {
            WarmCard {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Meeting Notes", systemImage: "doc.text")
                        .font(AppTheme.sectionHeaderFont)
                    Text(noteError)
                        .font(AppTheme.captionFont)
                        .foregroundStyle(AppTheme.urgencyRed)
                    Button("Retry") {
                        Task { await loadGranolaNote() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        } else if let detail = noteDetail {
            // Meeting Notes card
            if let markdown = detail.summaryMarkdown, !markdown.isEmpty {
                WarmCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Meeting Notes")
                                .font(AppTheme.sectionHeaderFont)
                            Spacer()
                            WorkspaceBadge(text: "Granola", color: AppTheme.badgeGranola)
                        }
                        MarkdownTextView(text: markdown)
                            .font(AppTheme.bodyFont)
                    }
                }
            } else if let text = detail.summaryText, !text.isEmpty {
                WarmCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Meeting Notes")
                                .font(AppTheme.sectionHeaderFont)
                            Spacer()
                            WorkspaceBadge(text: "Granola", color: AppTheme.badgeGranola)
                        }
                        Text(text)
                            .font(AppTheme.bodyFont)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }

            // Transcript
            if let transcript = detail.transcript, !transcript.isEmpty {
                transcriptSection(transcript)
            }

            // Convert AIs to Tasks button
            convertToTasksButton(detail)
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
                                .font(AppTheme.captionFont)
                                .fontWeight(.semibold)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        Text(segment.text)
                            .font(AppTheme.captionFont)
                    }
                    .padding(.vertical, 2)
                }
            }
        } label: {
            Text("Transcript")
                .font(AppTheme.sectionHeaderFont)
        }
    }

    // MARK: - Convert to Tasks

    @ViewBuilder
    private func convertToTasksButton(_ detail: GranolaNoteDetail) -> some View {
        let hasContent = (detail.summaryText != nil && detail.summaryText?.isEmpty == false)
            || (detail.summaryMarkdown != nil && detail.summaryMarkdown?.isEmpty == false)
        let hasClaudeKey = ((try? tokenManager.getClaudeAPIKey()) != nil)
        let hasAsana = tokenManager.isAsanaAuthenticated

        if hasContent && hasClaudeKey && hasAsana {
            Button {
                showConvertSheet = true
            } label: {
                Label("Convert AIs to Tasks", systemImage: "checklist")
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
            .controlSize(.regular)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Data Loading

    // MARK: - Zoom / Video Conference Cruft Stripping

    /// Strips boilerplate from video conferencing services (Zoom, Teams, etc.)
    /// Returns nil if the entire note was cruft.
    static func stripVideoConferenceCruft(_ text: String) -> String? {
        let lines = text.components(separatedBy: "\n")
        var filtered: [String] = []
        var skipping = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()

            // Start skipping at common Zoom / conferencing section markers
            if lower.hasPrefix("──────────")
                || lower.hasPrefix("-]")  // Zoom's "-::~:~::~:~:~:~:" delimiter
                || lower.contains("do not edit this section")
                || lower.contains("zoom meeting")  && lower.contains("join")
                || lower.hasPrefix("join zoom meeting")
                || lower.hasPrefix("join microsoft teams meeting")
                || lower.hasPrefix("join google meet")
                || lower.hasPrefix("meeting id:")
                || lower.hasPrefix("passcode:")
                || lower.hasPrefix("password:")
                || lower.hasPrefix("meeting password:")
                || lower.hasPrefix("one tap mobile")
                || lower.hasPrefix("dial by your location")
                || lower.hasPrefix("find your local number")
                || lower.hasPrefix("meeting host:")
                || lower.hasPrefix("host:")
                || lower == "-::~:~::~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~::~:~::-"
            {
                skipping = true
                continue
            }

            // Skip individual lines that are clearly conferencing boilerplate
            if isConferencingLine(lower) {
                continue
            }

            // Stop skipping at a blank line after cruft (possible real content follows)
            if skipping && trimmed.isEmpty {
                // Stay in skipping mode — consecutive blank lines in cruft sections
                continue
            }

            // If still skipping, check if this line looks like real content
            if skipping {
                if looksLikeRealContent(trimmed) {
                    skipping = false
                    filtered.append(line)
                }
                // Otherwise keep skipping
                continue
            }

            filtered.append(line)
        }

        let result = filtered.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private static func isConferencingLine(_ lower: String) -> Bool {
        // Zoom join link
        if lower.contains("zoom.us/j/") || lower.contains("zoom.us/w/") { return true }
        // Teams join link
        if lower.contains("teams.microsoft.com/l/meetup-join") { return true }
        // Google Meet link
        if lower.contains("meet.google.com/") && !lower.contains(" ") { return true }
        // Phone dial-in numbers (lines that are mostly digits, dashes, +, spaces)
        if lower.hasPrefix("+") && lower.filter({ $0.isNumber }).count >= 7 { return true }
        // Meeting ID / Passcode lines with numbers
        if (lower.hasPrefix("id:") || lower.hasPrefix("passcode:") || lower.hasPrefix("password:"))
            && lower.filter({ $0.isNumber }).count >= 3 { return true }
        // Webinar ID
        if lower.hasPrefix("webinar id:") { return true }
        // "US" or country dial-in labels
        if lower.count < 40 && lower.filter({ $0.isNumber }).count >= 7 { return true }
        // Zoom's separator
        if lower.contains("~:~:~:~") { return true }
        return false
    }

    private static func looksLikeRealContent(_ text: String) -> Bool {
        // Real content is typically a sentence or heading with enough alphabetic characters
        let alphaCount = text.filter({ $0.isLetter }).count
        return alphaCount >= 15 && !text.lowercased().contains("zoom") && !text.lowercased().contains("dial")
    }

    // MARK: - Data Loading

    private func loadGranolaNote() async {
        guard let noteID = meeting.granolaNoteID else { return }

        isLoadingNote = true
        noteError = nil

        do {
            if meetingNotes.isConfigured {
                noteDetail = try await meetingNotes.getNote(id: noteID)
            } else {
                noteDetail = try await granola.getNoteWithTranscript(id: noteID)
            }
        } catch {
            noteError = error.localizedDescription
        }

        isLoadingNote = false
    }
}
