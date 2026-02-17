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
            .navigationTitle("Tasks")
            .toolbar {
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
            taskSection(tasks: viewModel.overdueTasks, title: "Overdue", icon: "exclamationmark.triangle.fill", color: .red)
            taskSection(tasks: viewModel.dueTodayTasks, title: "Due Today", icon: "calendar.badge.exclamationmark", color: .orange)
            taskSection(tasks: viewModel.upcomingTasks, title: "Upcoming", icon: "calendar", color: .primary)
        }
        .insetGroupedListStyle()
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
                    .swipeActions(edge: .trailing) {
                        Button {
                            Task { await viewModel.completeTask(task) }
                        } label: {
                            Label("Complete", systemImage: "checkmark")
                        }
                        .tint(.green)
                    }
                }
            } header: {
                Label(title, systemImage: icon)
                    .foregroundStyle(color)
            }
        }
    }
}
