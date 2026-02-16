import Foundation
import SwiftUI

@Observable
@MainActor
final class ChatViewModel {
    var messages: [ChatMessage] = []
    var inputText = ""
    var isStreaming = false
    var error: String?

    private let chatService = ChatService()
    private var currentAssistantMessageID: UUID?

    init() {
        // Add welcome message
        messages.append(ChatMessage(
            role: .assistant,
            content: "Hi! I'm your personal assistant. I can help you with:\n\n- **Task management** - \"What's due today?\" or \"Create a task to...\"\n- **Meeting insights** - \"What did we discuss in...\" or \"Summarize my last meeting\"\n- **Daily planning** - \"What should I focus on?\" or \"Any overdue tasks?\"\n\nHow can I help you?"
        ))
    }

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }

        inputText = ""
        error = nil

        // Add user message
        messages.append(ChatMessage(role: .user, content: text))

        // Start streaming response
        Task {
            await streamResponse(userMessage: text)
        }
    }

    private func streamResponse(userMessage: String) async {
        isStreaming = true
        defer { isStreaming = false }

        // Create placeholder assistant message
        let assistantMessage = ChatMessage(role: .assistant, content: "")
        currentAssistantMessageID = assistantMessage.id
        messages.append(assistantMessage)

        do {
            let stopReason = try await chatService.sendMessage(
                userMessage,
                conversationHistory: Array(messages.dropLast()),
                onTextDelta: { [weak self] text in
                    self?.appendToCurrentMessage(text)
                },
                onToolCall: { [weak self] id, name, input in
                    self?.handleToolCall(id: id, name: name, input: input)
                }
            )

            // If Claude wants to use a tool, execute it and continue
            if stopReason == .toolUse {
                await processToolCalls()
            }
        } catch {
            self.error = error.localizedDescription
            appendToCurrentMessage("\n\n*Error: \(error.localizedDescription)*")
        }
    }

    private func appendToCurrentMessage(_ text: String) {
        guard let id = currentAssistantMessageID,
              let index = messages.firstIndex(where: { $0.id == id })
        else { return }

        messages[index].content += text
    }

    private func handleToolCall(id: String, name: String, input: [String: Any]) {
        guard let msgID = currentAssistantMessageID,
              let index = messages.firstIndex(where: { $0.id == msgID })
        else { return }

        let toolCall = ToolCallResult(id: id, name: name, input: input)
        if messages[index].toolCalls == nil {
            messages[index].toolCalls = []
        }
        messages[index].toolCalls?.append(toolCall)
    }

    private func processToolCalls() async {
        guard let msgID = currentAssistantMessageID,
              let index = messages.firstIndex(where: { $0.id == msgID }),
              let toolCalls = messages[index].toolCalls
        else { return }

        for (i, toolCall) in toolCalls.enumerated() {
            do {
                let result = try await chatService.executeTool(name: toolCall.name, input: toolCall.input)
                messages[index].toolCalls?[i].result = result
                messages[index].toolCalls?[i].isExecuting = false
            } catch {
                messages[index].toolCalls?[i].result = "Error: \(error.localizedDescription)"
                messages[index].toolCalls?[i].isExecuting = false
            }
        }

        // Send tool results back to Claude for final response
        let toolResults = messages[index].toolCalls?.compactMap { tc -> String? in
            guard let result = tc.result else { return nil }
            return "[\(tc.name)]: \(result)"
        }.joined(separator: "\n") ?? ""

        // Create a new assistant message for the follow-up
        let followUpMessage = ChatMessage(role: .assistant, content: "")
        currentAssistantMessageID = followUpMessage.id
        messages.append(followUpMessage)

        // Continue conversation with tool results
        do {
            // Add tool result as a user message for context
            let contextMessages = messages.dropLast()
            var history = Array(contextMessages)
            history.append(ChatMessage(role: .user, content: "Tool results:\n\(toolResults)"))

            _ = try await chatService.sendMessage(
                "Based on the tool results above, provide a natural response to the user.",
                conversationHistory: history,
                onTextDelta: { [weak self] text in
                    self?.appendToCurrentMessage(text)
                },
                onToolCall: { _, _, _ in }
            )
        } catch {
            appendToCurrentMessage("*Error processing tool results: \(error.localizedDescription)*")
        }
    }
}
