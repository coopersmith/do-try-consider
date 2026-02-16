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
                        .foregroundStyle(Color.accentColor)

                    Text("Claude AI")
                        .font(.headline)

                    Text("Enter your Anthropic API key to enable AI-powered briefings, chat, and task suggestions.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical)
                .frame(maxWidth: .infinity)
            }

            Section {
                if viewModel.isClaudeConfigured {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("API Key Configured")
                        Spacer()
                    }

                    Button(role: .destructive) {
                        viewModel.clearClaudeAPIKey()
                    } label: {
                        Label("Remove API Key", systemImage: "trash")
                    }
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
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        viewModel.saveClaudeAPIKey()
                    } label: {
                        Text("Save API Key")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.claudeAPIKey.isEmpty)
                }
            } header: {
                Text("API Key")
            } footer: {
                Text("Your API key is stored securely in the device Keychain. API calls are made directly from your device - there is no backend server.")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model")
                        .font(.subheadline)
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
            } header: {
                Text("Model Selection")
            } footer: {
                Text("Haiku is recommended for daily use (~$0.002/interaction). Sonnet provides more detailed analysis at higher cost.")
            }

            if let error = viewModel.claudeError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
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
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.systemGray6Color)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
