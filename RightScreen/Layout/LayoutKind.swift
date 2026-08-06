enum LayoutKind: String, CaseIterable, Sendable {
    case split2
    case split4

    var paneCount: Int {
        switch self {
        case .split2: 2
        case .split4: 4
        }
    }
}
