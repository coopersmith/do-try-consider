import SwiftUI

struct ClaudeSettingsView: View {
    @Environment(SettingsViewModel.self) private var viewModel
    @State private var showingAPIKey = false

    var body: some View {
        @Bindable var vm = viewModel

        List {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 48))
                        .foregroundStyle(AppTheme.accent)

                    Text("Claude AI")
                        .font(AppTheme.headlineFont)

                    Text("Enter your Anthropic API key to enable AI-powered briefings, chat, and task suggestions.")
                        .font(AppTheme.subheadlineFont)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical)
                .frame(maxWidth: .infinity)
                .listRowBackground(AppTheme.adaptiveCard)
            }

            Section {
                if viewModel.isClaudeConfigured {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.urgencyGreen)
                        Text("API Key Configured")
                        Spacer()
                    }
                    .listRowBackground(AppTheme.adaptiveCard)

                    Button(role: .destructive) {
                        viewModel.clearClaudeAPIKey()
                    } label: {
                        Label("Remove API Key", systemImage: "trash")
                    }
                    .listRowBackground(AppTheme.adaptiveCard)
                } else {
                    HStack {
                        if showingAPIKey {
                            TextField("sk-ant-...", text: $vm.claudeAPIKey)
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                #endif
                                .autocorrectionDisabled()
                        } else {
                            SecureField("sk-ant-...", text: $vm.claudeAPIKey)
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
                        viewModel.saveClaudeAPIKey()
                    } label: {
                        Text("Save API Key")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .disabled(viewModel.claudeAPIKey.isEmpty)
                    .listRowBackground(AppTheme.adaptiveCard)
                }
            } header: {
                Text("API Key")
            } footer: {
                Text("Your API key is stored securely in the device Keychain. API calls are made directly from your device - there is no backend server.")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model")
                        .font(AppTheme.subheadlineFont)
                        .fontWeight(.medium)

                    HStack(spacing: 12) {
                        ModelOption(
                            name: "Haiku",
                            description: "Fast & affordable",
                            isSelected: viewModel.selectedModel == .haiku
                        ) {
                            viewModel.selectedModel = .haiku
                        }

                        ModelOption(
                            name: "Sonnet",
                            description: "Most capable",
                            isSelected: viewModel.selectedModel == .sonnet
                        ) {
                            viewModel.selectedModel = .sonnet
                        }
                    }
                }
                .listRowBackground(AppTheme.adaptiveCard)
            } header: {
                Text("Model Selection")
            } footer: {
                Text("Haiku is recommended for daily use (~$0.002/interaction). Sonnet provides more detailed analysis at higher cost.")
            }

            if let error = viewModel.claudeError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(AppTheme.urgencyRed)
                        .font(AppTheme.captionFont)
                }
            }
        }
        .insetGroupedListStyle()
        .warmListBackground()
        .navigationTitle("Claude AI")
        .inlineNavigationBarTitle()
    }
}

struct ModelOption: View {
    let name: String
    let description: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(name)
                    .font(.system(.subheadline, design: .serif, weight: .semibold))
                Text(description)
                    .font(AppTheme.caption2Font)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? AppTheme.accent.opacity(0.12) : AppTheme.adaptiveSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                    .stroke(isSelected ? AppTheme.accent : Color.clear, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
        }
        .buttonStyle(.plain)
    }
}
