import Foundation
import Testing
import ThreadSafeKit

/// Swift files under `Sources/ThreadSafeKit`, keyed by path relative to the repo root.
private func librarySources() throws -> [(path: String, lines: [String])] {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let sources = root.appendingPathComponent("Sources/ThreadSafeKit")
    let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        .compactMap { $0 as? URL }
        .filter { $0.pathExtension == "swift" }
        .sorted { $0.path < $1.path }
    #expect(!files.isEmpty)
    return try files.map { file in
        let path = String(file.path.dropFirst(root.path.count + 1))
        return (path, try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n"))
    }
}

@Test func publicMembersAreInlinable() throws {
    var missing: [String] = []
    for (path, lines) in try librarySources() {
        var protocolDepth: Int?
        var depth = 0
        for (index, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if protocolDepth == nil, line.contains("protocol "), !line.hasPrefix("///") { protocolDepth = depth }
            defer {
                depth += line.filter { $0 == "{" }.count - line.filter { $0 == "}" }.count
                if let start = protocolDepth, depth <= start, line.contains("}") { protocolDepth = nil }
            }
            // Protocol requirements can't be inlinable, and stored properties have no body to inline.
            guard protocolDepth == nil, line.firstMatch(of: /^public\s+(?:(?:static|convenience|nonisolated)\s+)*(?:func|init|subscript|var)\b/) != nil else { continue }
            if line.hasPrefix("public var"), !line.contains("{") { continue }
            let attributes = lines[..<index].reversed()
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .prefix { $0.hasPrefix("@") || $0.hasPrefix("///") }
            if !attributes.contains("@inlinable") { missing.append("\(path):\(index + 1): \(line)") }
        }
    }
    #expect(missing.isEmpty, "Public members missing @inlinable (see README Contributing):\n\(missing.joined(separator: "\n"))")
}

@Test func actorsAreFinal() throws {
    var nonFinal: [String] = []
    for (path, lines) in try librarySources() {
        for (index, line) in lines.enumerated()
        where line.firstMatch(of: /^\s*public\s+actor\b/) != nil {
            nonFinal.append("\(path):\(index + 1): \(line)")
        }
    }
    #expect(nonFinal.isEmpty, "Public actors must be `final` (see README Contributing):\n\(nonFinal.joined(separator: "\n"))")
}

@Test func conformancesAreDeliberate() {
    // Checked through `Any.Type` so the compiler can't fold the casts; see docs/DECISIONS.md for why each is absent.
    let types: [Any.Type] = [
        ThreadSafe<Int>.self, ThreadSafe<[Int]>.self, ThreadSafe<[String: Int]>.self, ThreadSafe<Set<Int>>.self,
        ThreadSafeAtomic<Int>.self, ThreadSafeArray<Int>.self, ThreadSafeDictionary<String, Int>.self, ThreadSafeSet<Int>.self,
    ]
    for type in types {
        #expect(!(type is any Hashable.Type), "\(type) must not be Hashable")
        #expect(!(type is any Encodable.Type), "\(type) must not be Encodable")
        #expect(!(type is any Decodable.Type), "\(type) must not be Decodable")
    }
}
