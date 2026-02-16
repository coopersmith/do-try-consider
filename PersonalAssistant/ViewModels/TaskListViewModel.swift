import Foundation

@Observable
@MainActor
final class TaskListViewModel {
    var tasks: [AsanaTask] = []
    var workspaces: [AsanaWorkspace] = []
    var isLoading = false
    var error: String?

    // Filters
    var selectedWorkspace: AsanaWorkspace?
    var showCompleted = false
    var sortBy: SortOption = .dueDate

    enum SortOption: String, CaseIterable {
        case dueDate = "Due Date"
        case workspace = "Workspace"
        case name = "Name"
    }

    private let asana = AsanaAPIClient.shared
    private let tokenManager = TokenManager.shared

    var filteredTasks: [AsanaTask] {
        var result = tasks

        // Filter by workspace
        if let workspace = selectedWorkspace {
            result = result.filter { $0.workspace?.gid == workspace.gid }
        }

        // Filter completed
        if !showCompleted {
            result = result.filter { $0.completed != true }
        }

        // Sort
        switch sortBy {
        case .dueDate:
            result.sort { a, b in
                let aDate = a.dueDate ?? Date.distantFuture
                let bDate = b.dueDate ?? Date.distantFuture
                return aDate < bDate
            }
        case .workspace:
            result.sort { ($0.workspace?.name ?? "") < ($1.workspace?.name ?? "") }
        case .name:
            result.sort { $0.name < $1.name }
        }

        return result
    }

    var overdueTasks: [AsanaTask] {
        filteredTasks.filter { $0.isOverdue }
    }

    var dueTodayTasks: [AsanaTask] {
        filteredTasks.filter { $0.isDueToday }
    }

    var upcomingTasks: [AsanaTask] {
        filteredTasks.filter { task in
            !task.isOverdue && !task.isDueToday && task.completed != true
        }
    }

    // MARK: - Loading

    func loadTasks() async {
        guard tokenManager.isAsanaAuthenticated else {
            error = "Connect your Asana account in Settings."
            return
        }

        isLoading = true
        error = nil

        do {
            workspaces = try await asana.getWorkspaces()

            var allTasks: [AsanaTask] = []
            for workspace in workspaces {
                let tasks = try await asana.getMyTasks(
                    workspaceID: workspace.gid,
                    completedSince: showCompleted ? Calendar.current.date(byAdding: .day, value: -7, to: Date()) : Date()
                )
                allTasks.append(contentsOf: tasks)
            }

            tasks = allTasks
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func completeTask(_ task: AsanaTask) async {
        do {
            _ = try await asana.completeTask(id: task.gid)
            if let index = tasks.firstIndex(where: { $0.gid == task.gid }) {
                // Remove from list or mark as completed
                if !showCompleted {
                    tasks.remove(at: index)
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
