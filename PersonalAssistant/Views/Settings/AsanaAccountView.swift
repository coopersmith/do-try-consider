import SwiftUI

struct AsanaAccountView: View {
    @Environment(SettingsViewModel.self) private var viewModel
    @State private var showToken = false

    var body: some View {
        @Bindable var vm = viewModel

        List {
            if viewModel.isAsanaConnected {
                // Connected state
                Section {
                    if let user = viewModel.asanaUser {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.orange)

                            VStack(alignment: .leading) {
                                Text(user.name)
                                    .font(.headline)
                                if let email = user.email {
                                    Text(email)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Account")
                }

                // Workspaces
                if !viewModel.asanaWorkspaces.isEmpty {
                    Section {
                        ForEach(viewModel.asanaWorkspaces) { workspace in
                            HStack {
                                Image(systemName: workspace.isOrganization == true ? "building.2" : "person")
                                    .foregroundStyle(.secondary)
                                Text(workspace.displayName)
                                Spacer()
                                if workspace.isOrganization == true {
                                    Text("Organization")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("Workspaces (\(viewModel.asanaWorkspaces.count))")
                    }
                }

                // Disconnect
                Section {
                    Button(role: .destructive) {
                        viewModel.disconnectAsana()
                    } label: {
                        Label("Disconnect Asana", systemImage: "xmark.circle")
                    }
                }
            } else {
                // Not connected state
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "checklist")
                            .font(.system(size: 48))
                            .foregroundStyle(.orange)

                        Text("Connect Your Asana Account")
                            .font(.headline)

                        Text("Enter your Asana Personal Access Token to see your tasks, projects, and workspaces.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical)
                }

                Section {
                    HStack {
                        if showToken {
                            TextField("Asana Personal Access Token", text: $vm.asanaToken)
                                .textFieldStyle(.plain)
                        } else {
                            SecureField("Asana Personal Access Token", text: $vm.asanaToken)
                                .textFieldStyle(.plain)
                        }

                        Button {
                            showToken.toggle()
                        } label: {
                            Image(systemName: showToken ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        Task { await viewModel.saveAsanaToken() }
                    } label: {
                        HStack {
                            if viewModel.isSavingAsana {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text("Connect")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(viewModel.asanaToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSavingAsana)
                } footer: {
                    Text("Get your token from Asana → Settings → Apps → Developer Apps → Personal Access Token")
                }
            }

            // Error
            if let error = viewModel.asanaError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Asana")
        .inlineNavigationBarTitle()
        .task {
            await viewModel.loadAsanaInfo()
        }
    }
}
