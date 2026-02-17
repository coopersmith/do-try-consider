import Foundation

/// Read-only local markdown file reader for Obsidian-synced meeting notes.
/// Parses YAML frontmatter and returns Granola model types for seamless integration.
final class MeetingNotesReader: Sendable {
    static let shared = MeetingNotesReader()

    private let bookmarkKey = "meetingNotesBookmark"

    private init() {}

    // MARK: - Folder Access

    var isConfigured: Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    var folderName: String? {
        guard let url = resolveBookmark() else { return nil }
        return url.lastPathComponent
    }

    func setFolder(url: URL) throws {
        let bookmarkData = try url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
    }

    func clearFolder() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    // MARK: - Reading Notes

    func getRecentNotes(days: Int = 7) async throws -> [GranolaNoteListItem] {
        guard let folderURL = resolveBookmark() else {
            throw MeetingNotesError.noFolderConfigured
        }

        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let securityScoped = folderURL.startAccessingSecurityScopedResource()
        defer { if securityScoped { folderURL.stopAccessingSecurityScopedResource() } }

        let files = try markdownFiles(in: folderURL)
        var notes: [GranolaNoteListItem] = []

        for file in files {
            guard let parsed = parseMarkdownFile(at: file) else { continue }
            if let createdDate = parsed.createdDate, createdDate >= cutoff {
                notes.append(parsed.listItem)
            }
        }

        return notes.sorted { ($0.createdAt) > ($1.createdAt) }
    }

    func searchNotes(query: String) async throws -> [GranolaNoteListItem] {
        guard let folderURL = resolveBookmark() else {
            throw MeetingNotesError.noFolderConfigured
        }

        let securityScoped = folderURL.startAccessingSecurityScopedResource()
        defer { if securityScoped { folderURL.stopAccessingSecurityScopedResource() } }

        let files = try markdownFiles(in: folderURL)
        let queryWords = query.lowercased().split(separator: " ").map(String.init)
        var notes: [GranolaNoteListItem] = []

        for file in files {
            guard let parsed = parseMarkdownFile(at: file) else { continue }
            let titleLower = (parsed.title ?? "").lowercased()
            let bodyLower = parsed.body.lowercased()
            let combined = titleLower + " " + bodyLower
            let matches = queryWords.allSatisfy { combined.contains($0) }
            if matches {
                notes.append(parsed.listItem)
            }
        }

        return notes.sorted { ($0.createdAt) > ($1.createdAt) }
    }

    func getNote(id: String) async throws -> GranolaNoteDetail {
        guard let folderURL = resolveBookmark() else {
            throw MeetingNotesError.noFolderConfigured
        }

        let securityScoped = folderURL.startAccessingSecurityScopedResource()
        defer { if securityScoped { folderURL.stopAccessingSecurityScopedResource() } }

        let files = try markdownFiles(in: folderURL)

        for file in files {
            guard let parsed = parseMarkdownFile(at: file) else { continue }
            if parsed.noteID == id {
                return parsed.detail
            }
        }

        throw MeetingNotesError.noteNotFound
    }

    func fileCount() -> Int {
        guard let folderURL = resolveBookmark() else { return 0 }
        let securityScoped = folderURL.startAccessingSecurityScopedResource()
        defer { if securityScoped { folderURL.stopAccessingSecurityScopedResource() } }
        return (try? markdownFiles(in: folderURL).count) ?? 0
    }

    // MARK: - Private Helpers

    private func resolveBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        if isStale {
            // Re-save the bookmark if stale
            if let refreshed = try? url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                UserDefaults.standard.set(refreshed, forKey: bookmarkKey)
            }
        }

        return url
    }

    private func markdownFiles(in folder: URL) throws -> [URL] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        return contents.filter { $0.pathExtension == "md" }
    }

    // MARK: - Markdown Parsing

    private struct ParsedNote {
        let title: String?
        let createdAt: String
        let createdDate: Date?
        let noteID: String
        let people: [GranolaAttendee]
        let body: String

        var listItem: GranolaNoteListItem {
            GranolaNoteListItem(
                id: noteID,
                title: title,
                owner: nil,
                createdAt: createdAt,
                updatedAt: nil
            )
        }

        var detail: GranolaNoteDetail {
            GranolaNoteDetail(
                id: noteID,
                title: title,
                owner: nil,
                createdAt: createdAt,
                updatedAt: nil,
                calendarEvent: nil,
                attendees: people.isEmpty ? nil : people,
                folderMembership: nil,
                summaryText: body,
                summaryMarkdown: body,
                transcript: nil
            )
        }
    }

    private func parseMarkdownFile(at url: URL) -> ParsedNote? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        let (frontmatter, body) = extractFrontmatter(from: content)

        let title = frontmatter["title"]?.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        let createdAtRaw = frontmatter["created_at"] ?? ""
        let granolaID = frontmatter["granola_id"]
        let peopleRaw = frontmatter["people"]

        let createdDate = parseISO8601(createdAtRaw)
        let createdAt = createdAtRaw.isEmpty
            ? ISO8601DateFormatter().string(from: Date())
            : createdAtRaw

        let noteID: String
        if let gid = granolaID, !gid.isEmpty {
            noteID = gid
        } else {
            // Stable hash from filename
            noteID = "local-\(stableHash(url.lastPathComponent))"
        }

        let people = parsePeople(peopleRaw)

        return ParsedNote(
            title: title,
            createdAt: createdAt,
            createdDate: createdDate,
            noteID: noteID,
            people: people,
            body: body
        )
    }

    private func extractFrontmatter(from content: String) -> ([String: String], String) {
        var frontmatter: [String: String] = [:]
        var body = content

        guard content.hasPrefix("---") else { return (frontmatter, body) }

        let lines = content.components(separatedBy: "\n")
        guard lines.count >= 3 else { return (frontmatter, body) }

        var endIndex: Int?
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                endIndex = i
                break
            }
        }

        guard let end = endIndex else { return (frontmatter, body) }

        // Parse frontmatter lines
        for i in 1..<end {
            let line = lines[i]
            guard let colonRange = line.range(of: ":") else { continue }
            let key = String(line[line.startIndex..<colonRange.lowerBound])
                .trimmingCharacters(in: .whitespaces)
            let value = String(line[colonRange.upperBound...])
                .trimmingCharacters(in: .whitespaces)
            frontmatter[key] = value
        }

        // Body is everything after the closing ---
        let bodyLines = Array(lines[(end + 1)...])
        body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        return (frontmatter, body)
    }

    private func parsePeople(_ raw: String?) -> [GranolaAttendee] {
        guard let raw, !raw.isEmpty else { return [] }

        // Format: ["[[Name|email]]", "[[Name|email]]"]
        var attendees: [GranolaAttendee] = []
        let pattern = "\\[\\[([^|\\]]+)\\|?([^\\]]*)\\]\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let nsString = raw as NSString
        let matches = regex.matches(in: raw, range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            let name = match.range(at: 1).location != NSNotFound
                ? nsString.substring(with: match.range(at: 1))
                : nil
            let email = match.range(at: 2).location != NSNotFound
                ? nsString.substring(with: match.range(at: 2))
                : nil
            attendees.append(GranolaAttendee(
                name: name?.isEmpty == true ? nil : name,
                email: email?.isEmpty == true ? nil : email
            ))
        }

        return attendees
    }

    private func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private func stableHash(_ string: String) -> String {
        var hash: UInt64 = 5381
        for char in string.utf8 {
            hash = ((hash &<< 5) &+ hash) &+ UInt64(char)
        }
        return String(hash, radix: 16)
    }
}

// MARK: - Errors

enum MeetingNotesError: LocalizedError {
    case noFolderConfigured
    case noteNotFound

    var errorDescription: String? {
        switch self {
        case .noFolderConfigured:
            return "No meeting notes folder configured. Select your Obsidian folder in Settings."
        case .noteNotFound:
            return "Meeting note not found."
        }
    }
}
