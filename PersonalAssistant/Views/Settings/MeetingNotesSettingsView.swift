import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

struct MeetingNotesSettingsView: View {
    @Environment(SettingsViewModel.self) private var viewModel
    @State private var showingFolderPicker = false

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.indigo)

                    Text("Local Meeting Notes")
                        .font(AppTheme.headlineFont)

                    Text("Select your Obsidian meeting notes folder to access meeting notes, summaries, and attendee info directly from your device.")
                        .font(AppTheme.subheadlineFont)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical)
                .frame(maxWidth: .infinity)
                .listRowBackground(AppTheme.adaptiveCard)
            }

            Section {
                if viewModel.isMeetingNotesConfigured {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.urgencyGreen)
                        Text("Folder Connected")
                        Spacer()
                    }
                    .listRowBackground(AppTheme.adaptiveCard)

                    if let name = viewModel.meetingNotesFolderName {
                        HStack {
                            Text("Folder")
                            Spacer()
                            Text(name)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .listRowBackground(AppTheme.adaptiveCard)
                    }

                    HStack {
                        Text("Files")
                        Spacer()
                        Text("\(viewModel.meetingNotesFileCount) notes")
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .listRowBackground(AppTheme.adaptiveCard)

                    Button(role: .destructive) {
                        viewModel.clearMeetingNotesFolder()
                    } label: {
                        Label("Disconnect Folder", systemImage: "trash")
                    }
                    .listRowBackground(AppTheme.adaptiveCard)
                } else {
                    Button {
                        showingFolderPicker = true
                    } label: {
                        Label("Select Folder", systemImage: "folder.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .listRowBackground(AppTheme.adaptiveCard)
                }
            } header: {
                Text("Meeting Notes Folder")
            } footer: {
                Text("Select your Obsidian meeting notes folder. Read-only \u{2014} the app will never modify your vault.")
            }

            if let error = viewModel.meetingNotesError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(AppTheme.urgencyRed)
                        .font(AppTheme.captionFont)
                }
            }

            #if DEBUG
            Section("Debug") {
                Button("Use App Documents Folder") {
                    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    viewModel.selectMeetingNotesFolder(url: docs.appending(path: "ObsidianTestNotes"))
                }
                .font(AppTheme.captionFont)
                .foregroundStyle(.orange)
                .listRowBackground(AppTheme.adaptiveCard)
            }
            #endif
        }
        .insetGroupedListStyle()
        .warmListBackground()
        .navigationTitle("Meeting Notes")
        .inlineNavigationBarTitle()
        .onAppear { viewModel.refreshMeetingNotesStatus() }
        .sheet(isPresented: $showingFolderPicker) {
            FolderPickerView { url in
                viewModel.selectMeetingNotesFolder(url: url)
            }
        }
    }
}

// MARK: - Folder Picker

#if os(iOS)
struct FolderPickerView: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}
#else
struct FolderPickerView: View {
    let onPick: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Select a folder using Finder")
                .font(AppTheme.headlineFont)
            Button("Open Folder...") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                if panel.runModal() == .OK, let url = panel.url {
                    onPick(url)
                }
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
#endif
