import OSLog

typealias Tab = Workspace

let tabManagerLogger = Logger(subsystem: "com.cmuxterm.app", category: "TabManager")

enum WorkspaceOrderChangeNotificationKey {
    static let movedWorkspaceIds = "movedWorkspaceIds"
}
