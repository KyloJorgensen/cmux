import Bonsplit
import Foundation

#if DEBUG
func debugWorkspaceDescriptionPreview(_ text: String?, limit: Int = 120) -> String {
    guard let text else { return "nil" }
    let escaped = text
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\r", with: "\\r")
        .replacingOccurrences(of: "\t", with: "\\t")
    if escaped.count <= limit { return escaped }
    return "\(escaped.prefix(limit))..."
}
#endif

final class WorkspacePendingTerminalInputObserver: @unchecked Sendable {
    var observer: NSObjectProtocol?
}

struct SessionPaneRestoreEntry {
    let paneId: PaneID
    let snapshot: SessionPaneLayoutSnapshot
}

extension Workspace {
    enum BrowserPanelCreationPolicy {
        case userInitiated
        case automationPreload
        case restoration

        var permitsCreationWhenBrowserDisabled: Bool {
            self == .restoration
        }

        var preloadsInitialNavigationInBackground: Bool {
            self == .automationPreload
        }
    }
}
