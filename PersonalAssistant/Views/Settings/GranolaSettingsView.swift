import SwiftUI

struct GranolaSettingsView: View {
    @Environment(SettingsViewModel.self) private var viewModel
    @State private var showingAPIKey = false

    var body: some View {
        @Bindable var vm = viewModel

        List {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "note.text")
                        .font(.system(size: 48))
                        .foregroundStyle(AppTheme.badgeGranola)

                    Text("Granola Meeting Notes")
                        .font(AppTheme.headlineFont)

                    Text("Enter your Granola Enterprise API key to access your meeting notes, summaries, and transcripts.")
                        .font(AppTheme.subheadlineFont)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical)
                .frame(maxWidth: .infinity)
                .listRowBackground(AppTheme.adaptiveCard)
            }

            Section {
                if viewModel.isGranolaConfigured {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.urgencyGreen)
                        Text("API Key Configured")
                        Spacer()
                    }
                    .listRowBackground(AppTheme.adaptiveCard)

                    Button(role: .destructive) {
                        viewModel.clearGranolaAPIKey()
                    } label: {
                        Label("Remove API Key", systemImage: "trash")
                    }
                    .listRowBackground(AppTheme.adaptiveCard)
                } else {
                    HStack {
                        if showingAPIKey {
                            TextField("Enter API Key", text: $vm.granolaAPIKey)
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                #endif
                                .autocorrectionDisabled()
                        } else {
                            SecureField("Enter API Key", text: $vm.granolaAPIKey)
                        }

                        Button {
                            showingAPIKey.toggle()
                        } label: {
                            Image(systemName: showingAPIKey ? "eye.slash" : "eye")
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                    .listRowBackground(AppTheme.adaptiveCard)

                    Button {
                        viewModel.saveGranolaAPIKey()
                    } label: {
                        Text("Save API Key")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.badgeGranola)
                    .disabled(viewModel.granolaAPIKey.isEmpty)
                    .listRowBackground(AppTheme.adaptiveCard)
                }
            } header: {
                Text("API Key")
            } footer: {
                Text("Your API key is stored securely in the device Keychain and never leaves your device except to authenticate with Granola's API.")
            }

            if let error = viewModel.granolaError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(AppTheme.urgencyRed)
                        .font(AppTheme.captionFont)
                }
            }
        }
        .insetGroupedListStyle()
        .warmListBackground()
        .navigationTitle("Granola")
        .inlineNavigationBarTitle()
    }
}
