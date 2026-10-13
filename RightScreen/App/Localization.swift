import Foundation

/// 用户可见文案统一走这里：中文原文即查找键，翻译在 Resources/<语言>.lproj/Localizable.strings。
///
/// 找不到对应表时（如单测进程）原样返回中文键，因此逻辑与测试不依赖翻译文件。
/// 新增文案后需同时写入 en.lproj 与 zh-Hans.lproj，`LocalizationTests` 会检查遗漏。
func localized(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: nil, table: nil)
}

/// 带参数的文案：键里用 `%@` / `%ld` 占位，各语言可调整参数在句中的位置。
func localized(_ format: String, _ arguments: CVarArg...) -> String {
    String(format: localized(format), arguments: arguments)
}
