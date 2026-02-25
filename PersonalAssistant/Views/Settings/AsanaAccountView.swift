import SwiftUI

struct AsanaAccountView: View {
    @Environment(SettingsViewModel.self) private var viewModel

    var body: some View {
        List {
            if !viewModel.asanaAccountInfos.isEmpty {
                // Connected accounts
                ForEach(viewModel.asanaAccountInfos) { info in
                    Section {
                        // User info
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.orange)

                            VStack(alignment: .leading) {
                                Text(info.user.name)
                                    .font(AppTheme.headlineFont)
                                if let email = info.user.email {
                                    Text(email)
                                        .font(AppTheme.captionFont)
                                        .foregroundStyle(AppTheme.textSecondary)
                                }
                            }
                        }
                        .listRowBackground(AppTheme.adaptiveCard)

                        // Workspaces
                        if !info.workspaces.isEmpty {
                            ForEach(info.workspaces) { workspace in
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
                        }

                        // Disconnect this account
                        Button(role: .destructive) {
                            viewModel.disconnectAsanaAccount(id: info.id)
                        } label: {
                            Label("Disconnect", systemImage: "xmark.circle")
                        }
                        .listRowBackground(AppTheme.adaptiveCard)
                    } header: {
                        Text(info.user.name)
                    }
                }

                // Add another account
                Section {
                    Button {
                        Task { await viewModel.authenticateWithAsana() }
                    } label: {
                        HStack {
                            if viewModel.isSavingAsana {
                                ProgressView()
                                    .tint(.orange)
                            }
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.orange)
                            Text("Add Another Account")
                        }
                    }
                    .disabled(viewModel.isSavingAsana)
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

                        Text("Sign in with your Asana account to see your tasks, projects, and workspaces.")
                            .font(AppTheme.subheadlineFont)
                            .foregroundStyle(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical)
                    .listRowBackground(AppTheme.adaptiveCard)
                }

                Section {
                    Button {
                        Task { await viewModel.authenticateWithAsana() }
                    } label: {
                        HStack {
                            if viewModel.isSavingAsana {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text("Sign in with Asana")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(viewModel.isSavingAsana)
                    .listRowBackground(AppTheme.adaptiveCard)
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
