import AppKit
import CmuxSettings
import Foundation
import Testing
import WebKit

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite(.serialized)
struct BrowserWebExtensionSupportTests {
    @MainActor
    @Test
    @available(macOS 15.4, *)
    func keyWindowSwitchRestoresThatWindowsActiveExtensionTab() {
        let support = BrowserWebExtensionSupport()
        let firstPanel = BrowserPanel(
            workspaceId: UUID(),
            initialURL: URL(string: "https://first.example"),
            renderInitialNavigation: false,
            browserWebExtensionHost: support
        )
        let secondPanel = BrowserPanel(
            workspaceId: UUID(),
            initialURL: URL(string: "https://second.example"),
            renderInitialNavigation: false,
            browserWebExtensionHost: support
        )
        let firstWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let secondWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        firstWindow.contentView = firstPanel.webView
        secondWindow.contentView = secondPanel.webView
        defer {
            firstPanel.close()
            secondPanel.close()
            firstWindow.close()
            secondWindow.close()
        }

        support.register(panel: firstPanel)
        support.register(panel: secondPanel)
        support.noteActivated(panelID: firstPanel.id)
        support.noteActivated(panelID: secondPanel.id)
        #expect(support.activePanelID == secondPanel.id)

        support.noteWindowBecameKey(firstWindow)

        #expect(support.activePanelID == firstPanel.id)
        #expect((support.webExtensionWindow(for: firstWindow) as AnyObject?) === support.windowAdapter)
        let unrelatedWindow = NSWindow()
        #expect(support.webExtensionWindow(for: unrelatedWindow) == nil)

        support.unregister(panelID: firstPanel.id)
        #expect(support.activePanelID == nil)
        support.noteWindowBecameKey(secondWindow)
        #expect(support.activePanelID == secondPanel.id)
    }

    @MainActor
    @Test
    @available(macOS 15.4, *)
    func registeringBackgroundPanelDoesNotMakeItActive() {
        let support = BrowserWebExtensionSupport()
        let panel = BrowserPanel(
            workspaceId: UUID(),
            initialURL: URL(string: "https://background.example"),
            renderInitialNavigation: false,
            browserWebExtensionHost: support
        )
        defer { panel.close() }

        support.register(panel: panel)

        #expect(support.activePanelID == nil)
        support.noteActivated(panelID: panel.id)
        #expect(support.activePanelID == panel.id)
    }


    @MainActor
    @Test
    func pageInitiatedExtensionNavigationPolicyDistinguishesContextEntryAndExit() throws {
        let extensionURL = try #require(URL(string: "webkit-extension://cmux-test/options.html"))
        let normalURL = try #require(URL(string: "https://example.com/"))
        let unknownExtensionURL = try #require(URL(string: "webkit-extension://other-extension/options.html"))
        let fileURL = URL(fileURLWithPath: "/tmp/cmux-extension-test.txt")
        let host = BrowserWebExtensionNavigationPolicyTestHost(extensionHost: extensionURL.host)
        let panel = BrowserPanel(
            workspaceId: UUID(),
            initialURL: extensionURL,
            renderInitialNavigation: false,
            browserWebExtensionHost: host
        )
        defer { panel.close() }

        #expect(!panel.shouldBlockPageInitiatedWebExtensionNavigation(to: extensionURL))
        #expect(panel.shouldBlockPageInitiatedWebExtensionNavigation(to: unknownExtensionURL))
        #expect(panel.shouldBlockPageInitiatedWebExtensionNavigation(to: fileURL))
        #expect(!panel.shouldRoutePageInitiatedWebExtensionNavigationInCurrentTab(to: extensionURL))
        #expect(panel.shouldRoutePageInitiatedWebExtensionNavigationInCurrentTab(to: normalURL))
        #expect(!panel.shouldRoutePageInitiatedWebExtensionNavigationInCurrentTab(to: fileURL))
    }

    @MainActor
    @Test
    func extensionExitPreservesNilTargetNewTabIntent() {
        let delegate = BrowserNavigationDelegate()

        #expect(!delegate.shouldRouteWebExtensionNavigationAsCurrentTab(
            targetFrameIsMainFrame: nil,
            shouldOpenInNewTab: false,
            navigationType: .linkActivated
        ))
        #expect(!delegate.shouldRouteWebExtensionNavigationAsCurrentTab(
            targetFrameIsMainFrame: nil,
            shouldOpenInNewTab: false,
            navigationType: .other
        ))
        #expect(delegate.shouldRouteWebExtensionNavigationAsCurrentTab(
            targetFrameIsMainFrame: true,
            shouldOpenInNewTab: false,
            navigationType: .linkActivated
        ))
    }

    @Test
    @available(macOS 15.4, *)
    func permissionStateStorePersistsEntryStatesIndependently() throws {
        let suiteName = "cmux-web-extension-permissions-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = BrowserWebExtensionPermissionStateStore(defaults: defaults)
        let expiration = Date(timeIntervalSince1970: 1_800_000_000)
        let firstState = BrowserWebExtensionPermissionState(
            grantedPermissions: ["tabs": expiration],
            deniedPermissions: ["cookies": expiration],
            grantedPermissionMatchPatterns: ["https://example.com/*": expiration],
            deniedPermissionMatchPatterns: ["https://denied.example/*": expiration],
            hasRequestedOptionalAccessToAllHosts: true,
            hasAccessToPrivateData: false
        )
        let secondState = BrowserWebExtensionPermissionState(
            grantedPermissions: ["storage": expiration],
            deniedPermissions: [:],
            grantedPermissionMatchPatterns: [:],
            deniedPermissionMatchPatterns: [:],
            hasRequestedOptionalAccessToAllHosts: false,
            hasAccessToPrivateData: true
        )

        store.save(firstState, for: "com.example.first", standardizedPath: "/Extensions/First")
        store.save(secondState, for: "com.example.second", standardizedPath: "/Extensions/Second")

        #expect(store.state(for: "com.example.first", standardizedPath: "/Extensions/First") == firstState)
        #expect(store.state(for: "com.example.second", standardizedPath: "/Extensions/Second") == secondState)
        #expect(store.state(for: "missing", standardizedPath: "/Extensions/Missing") == nil)
    }

    @Test
    @available(macOS 15.4, *)
    func permissionStateDoesNotCrossResourceIdentities() throws {
        let suiteName = "cmux-web-extension-permission-identity-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = BrowserWebExtensionPermissionStateStore(defaults: defaults)
        let state = BrowserWebExtensionPermissionState(
            grantedPermissions: ["tabs": Date(timeIntervalSince1970: 1_800_000_000)],
            deniedPermissions: [:],
            grantedPermissionMatchPatterns: [:],
            deniedPermissionMatchPatterns: [:],
            hasRequestedOptionalAccessToAllHosts: false,
            hasAccessToPrivateData: false
        )

        store.save(state, for: "com.example.extension", standardizedPath: "/Extensions/Original")

        #expect(store.state(for: "com.example.extension", standardizedPath: "/Extensions/Original") == state)
        #expect(store.state(for: "com.example.extension", standardizedPath: "/Extensions/Replacement") == nil)
    }

    @Test
    @available(macOS 15.4, *)
    func permissionStateStoreRemovesOnlyTargetEntry() throws {
        let suiteName = "cmux-web-extension-permission-removal-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = BrowserWebExtensionPermissionStateStore(defaults: defaults)
        let expiration = Date(timeIntervalSince1970: 1_800_000_000)
        let firstState = BrowserWebExtensionPermissionState(
            grantedPermissions: ["tabs": expiration],
            deniedPermissions: [:],
            grantedPermissionMatchPatterns: [:],
            deniedPermissionMatchPatterns: [:],
            hasRequestedOptionalAccessToAllHosts: false,
            hasAccessToPrivateData: false
        )
        let secondState = BrowserWebExtensionPermissionState(
            grantedPermissions: ["storage": expiration],
            deniedPermissions: [:],
            grantedPermissionMatchPatterns: [:],
            deniedPermissionMatchPatterns: [:],
            hasRequestedOptionalAccessToAllHosts: false,
            hasAccessToPrivateData: false
        )

        store.save(firstState, for: "com.example.first", standardizedPath: "/Extensions/First")
        store.save(secondState, for: "com.example.second", standardizedPath: "/Extensions/Second")
        store.removeState(for: "com.example.first", standardizedPath: "/Extensions/First")

        #expect(store.state(for: "com.example.first", standardizedPath: "/Extensions/First") == nil)
        #expect(store.state(for: "com.example.second", standardizedPath: "/Extensions/Second") == secondState)
    }

    @Test
    func pluginkitParserHandlesVerboseSpaceSeparatedOutput() {
        let output = """
        +    com.bitwarden.desktop.safari(2026.7.0)  01234567-89AB-CDEF-0123-456789ABCDEF  2026-07-09 03:21:09 +0000  /Applications/Bitwarden.app/Contents/PlugIns/safari.appex
        -    com.example.disabled(1.2.3)\tAAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE\t2026-07-09 03:22:09 +0000\t/Applications/Example App.app/Contents/PlugIns/Example Extension.appex
        """

        let candidates = BrowserWebExtensionDiscoveryService.parse(pluginkitOutput: output)

        #expect(candidates.map(\.id) == [
            "com.bitwarden.desktop.safari",
            "com.example.disabled",
        ])
        #expect(candidates.first?.version == "2026.7.0")
        #expect(candidates.first?.path == "/Applications/Bitwarden.app/Contents/PlugIns/safari.appex")
        #expect(candidates.last?.version == "1.2.3")
        #expect(candidates.last?.path == "/Applications/Example App.app/Contents/PlugIns/Example Extension.appex")
    }

    @MainActor
    @Test
    @available(macOS 15.4, *)
    func extensionCreatesFirstBrowserTabInActiveTerminalWindow() throws {
        let defaults = UserDefaults.standard
        let originalDisabledValue = defaults.object(forKey: BrowserAvailabilitySettings.disabledKey)
        BrowserAvailabilitySettings.setDisabled(false, defaults: defaults)
        defer {
            if let originalDisabledValue {
                defaults.set(originalDisabledValue, forKey: BrowserAvailabilitySettings.disabledKey)
            } else {
                defaults.removeObject(forKey: BrowserAvailabilitySettings.disabledKey)
            }
            NotificationCenter.default.post(
                name: BrowserAvailabilitySettings.didChangeNotification,
                object: nil
            )
        }

        let support = BrowserWebExtensionSupport()
        let tabManager = TabManager(browserWebExtensionHost: support)
        let workspace = try #require(tabManager.selectedWorkspace)
        #expect(workspace.panels.values.allSatisfy { !($0 is BrowserPanel) })

        let adapter = support.openBrowserTab(
            in: tabManager,
            url: nil,
            shouldActivate: false,
            webViewConfiguration: nil
        )

        let panel = try #require(adapter?.panel)
        defer { _ = workspace.closePanel(panel.id, force: true) }
        #expect(panel.workspaceId == workspace.id)
        #expect(workspace.panels[panel.id] === panel)
    }

    @MainActor
    @Test
    func configuredCmuxShortcutTakesPriorityOverExtensionCommand() throws {
        let appDelegate = try #require(AppDelegate.shared)
        let action = KeyboardShortcutSettings.Action.openBrowser
        let hadPersistedShortcut = UserDefaults.standard.object(forKey: action.defaultsKey) != nil
        let originalShortcut = KeyboardShortcutSettings.shortcut(for: action)
        defer {
            if hadPersistedShortcut {
                KeyboardShortcutSettings.setShortcut(originalShortcut, for: action)
            } else {
                KeyboardShortcutSettings.resetShortcut(for: action)
            }
        }
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .shift],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: "L",
            charactersIgnoringModifiers: "l",
            isARepeat: false,
            keyCode: 37
        ))

        KeyboardShortcutSettings.setShortcut(action.defaultShortcut, for: action)
        #expect(!appDelegate.shouldOfferBrowserWebExtensionCommand(event))

        KeyboardShortcutSettings.setShortcut(.unbound, for: action)
        #expect(appDelegate.shouldOfferBrowserWebExtensionCommand(event))
    }

    @MainActor
    @Test
    @available(macOS 15.4, *)
    func extensionPagePanelLookupMatchesTheOwningContextOnly() throws {
        let extensionURL = try #require(URL(string: "webkit-extension://cmux-test/options.html"))
        let host = BrowserWebExtensionNavigationPolicyTestHost(extensionHost: extensionURL.host)
        let panel = BrowserPanel(
            workspaceId: UUID(),
            initialURL: extensionURL,
            renderInitialNavigation: false,
            browserWebExtensionHost: host
        )
        let support = BrowserWebExtensionSupport()
        support.register(panel: panel)
        defer {
            support.unregister(panelID: panel.id)
            panel.close()
        }

        #expect(
            support.extensionPagePanels(usingContextIdentifier: host.contextIdentifier).map(\.id) == [panel.id]
        )
        #expect(
            support.extensionPagePanels(usingContextIdentifier: ObjectIdentifier(NSObject())).isEmpty
        )
    }

    @Test
    func standardizedExtensionPathResolvesSymlinkAliases() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-web-extension-symlink-\(UUID().uuidString)", isDirectory: true)
        let extensionDirectory = tempDirectory.appendingPathComponent("Extension", isDirectory: true)
        let aliasURL = tempDirectory.appendingPathComponent("Extension Alias", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        try FileManager.default.createDirectory(at: extensionDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: aliasURL, withDestinationURL: extensionDirectory)

        #expect(
            BrowserWebExtensionEntry.standardizedPath(aliasURL.path)
                == BrowserWebExtensionEntry.standardizedPath(extensionDirectory.path)
        )
    }

    @MainActor
    @Test
    @available(macOS 15.4, *)
    func removingFailedExtensionClearsOnlyItsLoadError() {
        let support = BrowserWebExtensionSupport()
        support.loadErrorsByEntryID = [
            "keep": "keep: still failed",
            "remove": "remove: stale failure",
        ]
        support.discardLoadErrorsNotInDesiredEntries([
            BrowserWebExtensionEntry(
                id: "keep",
                kind: .unpackedDirectory,
                path: "/tmp/keep",
                enabled: true
            ),
        ])

        #expect(support.loadErrorsByEntryID == ["keep": "keep: still failed"])
        #expect(support.loadErrors == ["keep: still failed"])
    }

    @Test
    func ordinaryPopupBlocksWebExtensionURLs() throws {
        let extensionURL = try #require(URL(string: "webkit-extension://example/options.html"))
        let webURL = try #require(URL(string: "https://example.com"))

        #expect(browserNavigationShouldBlockWebExtensionURLInOrdinaryPopup(extensionURL))
        #expect(!browserNavigationShouldBlockWebExtensionURLInOrdinaryPopup(webURL))
    }

    @Test
    @available(macOS 15.4, *)
    func extensionWindowPolicyRejectsDroppedTabsAndURLs() {
        #expect(browserWebExtensionCanRepresentNewWindow(
            type: .popup,
            shouldBePrivate: false,
            tabURLCount: 1,
            existingTabCount: 0
        ))
        #expect(!browserWebExtensionCanRepresentNewWindow(
            type: .popup,
            shouldBePrivate: false,
            tabURLCount: 2,
            existingTabCount: 0
        ))
        #expect(!browserWebExtensionCanRepresentNewWindow(
            type: .normal,
            shouldBePrivate: false,
            tabURLCount: 0,
            existingTabCount: 1
        ))
        #expect(!browserWebExtensionCanRepresentNewWindow(
            type: .normal,
            shouldBePrivate: true,
            tabURLCount: 0,
            existingTabCount: 0
        ))
    }
}

@MainActor
final class BrowserWebExtensionNavigationPolicyTestHost: BrowserWebExtensionHosting {
    private let extensionHost: String?
    private let contextToken = NSObject()
    private let configuration = WKWebViewConfiguration()

    var contextIdentifier: ObjectIdentifier {
        ObjectIdentifier(contextToken)
    }

    init(extensionHost: String?) {
        self.extensionHost = extensionHost
    }

    func attach(to configuration: WKWebViewConfiguration) {}

    func webViewConfiguration(forNavigatingTo url: URL) -> BrowserWebExtensionNavigationConfiguration? {
        guard url.scheme?.lowercased() == "webkit-extension",
              url.host == extensionHost else { return nil }
        return BrowserWebExtensionNavigationConfiguration(
            contextIdentifier: ObjectIdentifier(contextToken),
            webViewConfiguration: configuration
        )
    }

    func register(panel: BrowserPanel) {}

    func unregister(panelID: UUID) {}

    func noteActivated(panelID: UUID) {}

    func noteTabMetadataChanged(panelID: UUID) {}

    func performCommand(for event: NSEvent) -> Bool { false }
}
