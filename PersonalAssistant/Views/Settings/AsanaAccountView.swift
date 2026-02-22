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
                                    .font(AppTheme.headlineFont)
                                if let email = user.email {
                                    Text(email)
                                        .font(AppTheme.captionFont)
                                        .foregroundStyle(AppTheme.textSecondary)
                                }
                            }
                        }
                        .listRowBackground(AppTheme.adaptiveCard)
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
                                    .foregroundStyle(AppTheme.textSecondary)
                                Text(workspace.displayName)
                                Spacer()
                                if workspace.isOrganization == true {
                                    Text("Organization")
                                        .font(AppTheme.captionFont)
                                        .foregroundStyle(AppTheme.textSecondary)
                                }
                            }
                            .listRowBackground(AppTheme.adaptiveCard)
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
                    .listRowBackground(AppTheme.adaptiveCard)
                }
            } else {
                // Not connected state
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "checklist")
                            .font(.system(size: 48))
                            .foregroundStyle(.orange)

                        Text("Connect Your Asana Account")
                            .font(AppTheme.headlineFont)

                        Text("Enter your Asana Personal Access Token to see your tasks, projects, and workspaces.")
                            .font(AppTheme.subheadlineFont)
                            .foregroundStyle(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical)
                    .listRowBackground(AppTheme.adaptiveCard)
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
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .listRowBackground(AppTheme.adaptiveCard)

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
                    .listRowBackground(AppTheme.adaptiveCard)
                } footer: {
                    Text("Get your token from Asana \u{2192} Settings \u{2192} Apps \u{2192} Developer Apps \u{2192} Personal Access Token")
                }
            }

            // Error
            if let error = viewModel.asanaError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(AppTheme.urgencyRed)
                        .font(AppTheme.captionFont)
                }
            }
        }
        .insetGroupedListStyle()
        .warmListBackground()
        .navigationTitle("Asana")
        .inlineNavigationBarTitle()
        .task {
            await viewModel.loadAsanaInfo()
        }
    }
}
