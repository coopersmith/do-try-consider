import Combine
import SwiftUI

struct ChatOverlayView: View {
    @Bindable var viewModel: ChatViewModel
    @FocusState private var isInputFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            ChatBubbleView(message: message)
                                .id(message.id)
                        }

                        if viewModel.isStreaming {
                            HStack {
                                TypingIndicator()
                                Spacer()
                            }
                            .padding(.horizontal)
                            .id("typing")
                        }
                    }
                    .padding(.vertical)
                }
                .warmScrollBackground()
                .onChange(of: viewModel.messages.count) {
                    withAnimation {
                        if let lastID = viewModel.messages.last?.id {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: viewModel.messages.last?.content) {
                    proxy.scrollTo(viewModel.messages.last?.id, anchor: .bottom)
                }
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 0) {
                        // Error banner
                        if let error = viewModel.error {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.yellow)
                                Text(error)
                                    .font(AppTheme.captionFont)
                                    .foregroundStyle(AppTheme.textSecondary)
                                Spacer()
                                Button { viewModel.error = nil } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(AppTheme.textSecondary)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                        }

                        Divider()

                        // Input bar
                        HStack(spacing: 12) {
                            TextField("Ask me anything...", text: $viewModel.inputText, axis: .vertical)
                                .textFieldStyle(.plain)
                                .lineLimit(1...5)
                                .focused($isInputFocused)
                                .onSubmit {
                                    viewModel.sendMessage()
                                }

                            Button {
                                viewModel.sendMessage()
                            } label: {
                                Image(systemName: viewModel.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : AppTheme.accent)
                            }
                            .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isStreaming)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                    }
                    .background(.ultraThinMaterial)
                }
            }
            .navigationTitle("Chat")
            .inlineNavigationBarTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Chat Bubble

struct ChatBubbleView: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                // Tool calls display
                if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    ForEach(toolCalls) { tool in
                        ToolCallBadge(toolCall: tool)
                    }
                }

                // Message content
                if !message.content.isEmpty {
                    MarkdownTextView(text: message.content)
                        .padding(12)
                        .background(message.role == .user ? AppTheme.accent : AppTheme.adaptiveCard)
                        .foregroundStyle(message.role == .user ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
                }

                // Timestamp
                Text(DateFormatting.time(message.timestamp))
                    .font(AppTheme.caption2Font)
                    .foregroundStyle(.tertiary)
            }

            if message.role == .assistant {
                Spacer(minLength: 60)
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Tool Call Badge

struct ToolCallBadge: View {
    let toolCall: ToolCallResult

    var body: some View {
        HStack(spacing: 6) {
            if toolCall.isExecuting {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Image(systemName: toolCall.result?.hasPrefix("Error") == true ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(toolCall.result?.hasPrefix("Error") == true ? AppTheme.urgencyRed : AppTheme.urgencyGreen)
            }

            Text(toolDisplayName)
                .font(AppTheme.captionFont)
                .fontWeight(.medium)

            if let result = toolCall.result, !toolCall.isExecuting {
                Text(result.prefix(50) + (result.count > 50 ? "..." : ""))
                    .font(AppTheme.caption2Font)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AppTheme.adaptiveSecondary)
        .clipShape(Capsule())
    }

    private var toolDisplayName: String {
        switch toolCall.name {
        case "create_asana_task": return "Creating task"
        case "complete_asana_task": return "Completing task"
        case "get_tasks_due": return "Fetching tasks"
        case "search_meeting_notes": return "Searching meetings"
        case "update_asana_task": return "Updating task"
        case "get_task_comments": return "Fetching comments"
        case "add_task_comment": return "Adding comment"
        default: return toolCall.name
        }
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var dotCount = 0
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(AppTheme.textSecondary)
                    .frame(width: 6, height: 6)
                    .opacity(dotCount % 3 == i ? 1 : 0.3)
            }
        }
        .padding(12)
        .background(AppTheme.adaptiveCard)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium))
        .onReceive(timer) { _ in
            dotCount += 1
        }
    }
}
