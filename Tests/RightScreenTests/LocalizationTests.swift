import Foundation
import Testing
@testable import RightScreen

/// 源码里每条 `localized("…")` 都必须在 en / zh-Hans 翻译表中有对应项，且占位符一致。
struct LocalizationTests {
    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // RightScreenTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent()

    private static let languages = ["en", "zh-Hans"]

    @Test func everySourceKeyIsTranslatedInEveryLanguage() throws {
        let keys = try Self.sourceKeys()
        #expect(keys.count > 50)

        for language in Self.languages {
            let table = try Self.table(language)
            let missing = keys.subtracting(table.keys).sorted()
            #expect(missing.isEmpty, "\(language) 缺少翻译：\(missing)")
            let unused = Set(table.keys).subtracting(keys).sorted()
            #expect(unused.isEmpty, "\(language) 有源码已不再使用的键：\(unused)")
        }
    }

    @Test func translationsKeepTheSameFormatSpecifiers() throws {
        for language in Self.languages {
            for (key, value) in try Self.table(language) {
                #expect(
                    Self.specifiers(in: key) == Self.specifiers(in: value),
                    "\(language) 占位符不一致：\(key) → \(value)"
                )
            }
        }
    }

    @Test func missingTableFallsBackToChineseKey() {
        // 单测进程没有翻译表，界面逻辑拿到的仍是中文原文。
        #expect(LayoutKind.fullScreen.menuTitle == "全屏")
        #expect(LayoutKind.fullScreen.menuSubtitle == "1 格")
        #expect(LayoutKind.split4.menuSubtitle == "4 格")
    }

    private static func table(_ language: String) throws -> [String: String] {
        let url = repositoryRoot.appendingPathComponent("RightScreen/Resources/\(language).lproj/Localizable.strings")
        let data = try Data(contentsOf: url)
        return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
    }

    private static func sourceKeys() throws -> Set<String> {
        let sourceRoot = repositoryRoot.appendingPathComponent("RightScreen")
        let files = FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []

        let singleLine = try NSRegularExpression(pattern: #"localized\("(?!"")((?:[^"\\]|\\.)*)""#)
        let multiLine = try NSRegularExpression(
            pattern: #"localized\(\s*"""\n(.*?)\n([ \t]*)""""#,
            options: [.dotMatchesLineSeparators]
        )

        var keys = Set<String>()
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(source.startIndex..., in: source)
            for match in singleLine.matches(in: source, range: range) {
                keys.insert(String(source[Range(match.range(at: 1), in: source)!]))
            }
            for match in multiLine.matches(in: source, range: range) {
                let body = String(source[Range(match.range(at: 1), in: source)!])
                let indent = String(source[Range(match.range(at: 2), in: source)!])
                // 与 Swift 多行字面量相同：按结束分隔符的缩进去掉每行前缀。
                let lines = body.split(separator: "\n", omittingEmptySubsequences: false).map { line in
                    line.hasPrefix(indent) ? String(line.dropFirst(indent.count)) : String(line)
                }
                keys.insert(lines.joined(separator: "\n"))
            }
        }
        return keys
    }

    private static func specifiers(in text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"%(?:\d+\$)?(?:@|ld|d)"#)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .map { String(text[Range($0.range, in: text)!]) }
            .sorted()
    }
}
