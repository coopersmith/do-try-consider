import SwiftUI

struct TaskListView: View {
    @State private var viewModel = TaskListViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.tasks.isEmpty {
                    LoadingIndicator("Loading tasks...")
                } else if let error = viewModel.error, viewModel.tasks.isEmpty {
                    ErrorStateView(error) {
                        Task { await viewModel.loadTasks() }
                    }
                } else if viewModel.filteredTasks.isEmpty {
                    EmptyStateView(
                        icon: "checkmark.circle",
                        title: "All Clear",
                        message: viewModel.tasks.isEmpty
                            ? "Connect your Asana account to see tasks."
                            : "No tasks match your current filters."
                    )
                } else {
                    taskList
                }
            }
            .background(AppTheme.adaptiveBackground)
            .inlineNavigationBarTitle()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Tasks")
                        .font(AppTheme.subheadlineFont)
                        .fontWeight(.medium)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                ToolbarItem(placement: .automatic) {
                    filterMenu
                }
            }
            .refreshable {
                await viewModel.loadTasks()
            }
            .task {
                if viewModel.tasks.isEmpty {
                    await viewModel.loadTasks()
                }
            }
            .onChange(of: viewModel.showCompleted) {
                Task { await viewModel.loadTasks() }
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            sortSection
            if viewModel.workspaces.count > 1 {
                workspaceSection
            }
            Section {
                Toggle("Show Completed", isOn: $viewModel.showCompleted)
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(AppTheme.accent)
        }
    }

    private var sortSection: some View {
        Section("Sort By") {
            ForEach(TaskListViewModel.SortOption.allCases, id: \.self) { option in
                Button {
                    viewModel.sortBy = option
                } label: {
                    HStack {
                        Text(option.rawValue)
                        Spacer()
                        if viewModel.sortBy == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
    }

    private var workspaceSection: some View {
        Section("Workspace") {
            Button {
                viewModel.selectedWorkspace = nil
            } label: {
                HStack {
                    Text("All Workspaces")
                    Spacer()
                    if viewModel.selectedWorkspace == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }
            ForEach(viewModel.workspaces) { ws in
                Button {
                    viewModel.selectedWorkspace = ws
                } label: {
                    HStack {
                        Text(ws.displayName)
                        Spacer()
                        if viewModel.selectedWorkspace?.gid == ws.gid {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
    }

    private var taskList: some View {
        List {
            taskSection(tasks: viewModel.overdueTasks, title: "OVERDUE", icon: "exclamationmark.triangle.fill", color: AppTheme.urgencyRed)
            taskSection(tasks: viewModel.dueTodayTasks, title: "DUE TODAY", icon: "calendar.badge.exclamationmark", color: AppTheme.urgencyOrange)
            taskSection(tasks: viewModel.upcomingTasks, title: "UPCOMING", icon: "calendar", color: AppTheme.textPrimary)
        }
        .insetGroupedListStyle()
        .warmListBackground()
        .navigationDestination(for: String.self) { taskID in
            TaskDetailView(taskID: taskID)
        }
    }

    @ViewBuilder
    private func taskSection(tasks: [AsanaTask], title: String, icon: String, color: Color) -> some View {
        if !tasks.isEmpty {
            Section {
                ForEach(tasks) { task in
                    NavigationLink(value: task.gid) {
                        TaskRowView(task: task)
                    }
                    .listRowBackground(AppTheme.adaptiveCard)
                    .swipeActions(edge: .trailing) {
                        Button {
                            Task { await viewModel.completeTask(task) }
                        } label: {
                            Label("Complete", systemImage: "checkmark")
                        }
                        .tint(AppTheme.urgencyGreen)
                    }
                }
            } header: {
                Label(title, systemImage: icon)
                    .font(AppTheme.captionFont)
                    .fontWeight(.semibold)
                    .tracking(0.8)
                    .foregroundStyle(color)
            }
        }
    }
}
