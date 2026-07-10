import CmuxSettings

@MainActor
enum BrowserWebExtensionHostFactory {
    static func make(
        jsonStore: JSONConfigStore,
        catalog: SettingCatalog
    ) -> (any BrowserWebExtensionHosting)? {
        guard #available(macOS 15.4, *) else { return nil }
        let support = BrowserWebExtensionSupport()
        support.configure(
            jsonStore: jsonStore,
            catalog: catalog
        )
        StartupBreadcrumbLog.append("app.init.browserWebExtensions.configured")
        return support
    }
}
