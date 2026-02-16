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
                        .foregroundStyle(.purple)

                    Text("Granola Meeting Notes")
                        .font(.headline)

                    Text("Enter your Granola Enterprise API key to access your meeting notes, summaries, and transcripts.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical)
                .frame(maxWidth: .infinity)
            }

            Section {
                if viewModel.isGranolaConfigured {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("API Key Configured")
                        Spacer()
                    }

                    Button(role: .destructive) {
                        viewModel.clearGranolaAPIKey()
                    } label: {
                        Label("Remove API Key", systemImage: "trash")
                    }
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
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        viewModel.saveGranolaAPIKey()
                    } label: {
                        Text("Save API Key")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(viewModel.granolaAPIKey.isEmpty)
                }
            } header: {
                Text("API Key")
            } footer: {
                Text("Your API key is stored securely in the device Keychain and never leaves your device except to authenticate with Granola's API.")
            }

            if let error = viewModel.granolaError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Granola")
        .inlineNavigationBarTitle()
    }
}
