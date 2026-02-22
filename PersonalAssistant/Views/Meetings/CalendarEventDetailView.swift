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
                if let notes = meeting.notes, !notes.isEmpty {
                    WarmCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Event Notes")
                                .font(AppTheme.sectionHeaderFont)
                            Text(notes)
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
