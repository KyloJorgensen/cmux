import CmuxSettings
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite(.serialized)
struct BrowserWebExtensionReconciliationPlannerTests {
    @Test
    func reconciliationSkipsEnvPathWhenSettingsEntryIsDisabled() {
        let planner = BrowserWebExtensionReconciliationPlanner()
        let appexPath = "/Applications/Bitwarden.app/Contents/PlugIns/safari.appex"
        let plan = planner.plan(
            settingsEntries: [
                BrowserWebExtensionEntry(
                    id: "com.bitwarden.desktop.safari",
                    kind: .safariAppExtension,
                    path: appexPath,
                    enabled: false
                ),
            ],
            environmentPaths: [appexPath],
            loadedEntries: []
        )

        #expect(plan.desiredEntries.isEmpty)
        #expect(plan.loadEntries.isEmpty)
        #expect(plan.unloadEntryIDs.isEmpty)
    }

    @Test
    func reconciliationSkipsEnvResourceRootWhenSettingsEntryIsDisabled() {
        let planner = BrowserWebExtensionReconciliationPlanner()
        let appexPath = "/Applications/Bitwarden.app/Contents/PlugIns/safari.appex"
        let resourcePath = "\(appexPath)/Contents/Resources"
        let plan = planner.plan(
            settingsEntries: [
                BrowserWebExtensionEntry(
                    id: "com.bitwarden.desktop.safari",
                    kind: .safariAppExtension,
                    path: appexPath,
                    enabled: false
                ),
            ],
            environmentPaths: [resourcePath],
            loadedEntries: []
        )

        #expect(plan.desiredEntries.isEmpty)
        #expect(plan.loadEntries.isEmpty)
        #expect(plan.unloadEntryIDs.isEmpty)
    }

    @Test
    func reconciliationDoesNotLoadSamePathTwice() {
        let planner = BrowserWebExtensionReconciliationPlanner()
        let appexPath = "/Applications/Bitwarden.app/Contents/PlugIns/safari.appex"
        let plan = planner.plan(
            settingsEntries: [
                BrowserWebExtensionEntry(
                    id: "com.bitwarden.desktop.safari",
                    kind: .safariAppExtension,
                    path: appexPath,
                    enabled: true
                ),
            ],
            environmentPaths: [appexPath],
            loadedEntries: []
        )

        #expect(plan.desiredEntries.map(\.id) == ["com.bitwarden.desktop.safari"])
        #expect(plan.loadEntries.map(\.id) == ["com.bitwarden.desktop.safari"])
    }

    @Test
    func reconciliationDoesNotLoadBundleAndResourceRootTwice() {
        let planner = BrowserWebExtensionReconciliationPlanner()
        let appexPath = "/Applications/Bitwarden.app/Contents/PlugIns/safari.appex"
        let resourcePath = "\(appexPath)/Contents/Resources"
        let plan = planner.plan(
            settingsEntries: [
                BrowserWebExtensionEntry(
                    id: "com.bitwarden.desktop.safari",
                    kind: .safariAppExtension,
                    path: appexPath,
                    enabled: true
                ),
                BrowserWebExtensionEntry(
                    id: resourcePath,
                    kind: .unpackedDirectory,
                    path: resourcePath,
                    enabled: true
                ),
            ],
            environmentPaths: [],
            loadedEntries: []
        )

        #expect(plan.desiredEntries.map(\.id) == ["com.bitwarden.desktop.safari"])
        #expect(plan.loadEntries.map(\.id) == ["com.bitwarden.desktop.safari"])
    }

    @Test
    func reconciliationKeepsLoadedSafariExtensionWhenResourceRootMatches() {
        let planner = BrowserWebExtensionReconciliationPlanner()
        let appexPath = "/Applications/Bitwarden.app/Contents/PlugIns/safari.appex"
        let resourcePath = BrowserWebExtensionEntry.standardizedSafariAppExtensionResourceRootPath(appexPath)
        let plan = planner.plan(
            settingsEntries: [
                BrowserWebExtensionEntry(
                    id: "com.bitwarden.desktop.safari",
                    kind: .safariAppExtension,
                    path: appexPath,
                    enabled: true
                ),
            ],
            environmentPaths: [],
            loadedEntries: [
                BrowserWebExtensionReconciliationPlanner.LoadedEntry(
                    id: "com.bitwarden.desktop.safari",
                    standardizedPath: resourcePath
                ),
            ]
        )

        #expect(plan.unloadEntryIDs.isEmpty)
        #expect(plan.loadEntries.isEmpty)
    }

    @Test
    func reconciliationDeduplicatesRepeatedEnvironmentPaths() {
        let planner = BrowserWebExtensionReconciliationPlanner()
        let extensionPath = "/tmp/cmux-web-extensions/../cmux-web-extensions/Example"
        let standardizedPath = BrowserWebExtensionReconciliationPlanner.standardizedPath(extensionPath)
        let plan = planner.plan(
            settingsEntries: [],
            environmentPaths: [
                extensionPath,
                standardizedPath,
            ],
            loadedEntries: []
        )

        #expect(plan.desiredEntries.map(\.id) == [extensionPath])
        #expect(plan.desiredEntries.map(\.path) == [extensionPath])
        #expect(plan.loadEntries.map(\.id) == [extensionPath])
        #expect(plan.unloadEntryIDs.isEmpty)
    }

    @Test
    func reconciliationReloadsWhenPathChangesForSameEntryID() {
        let planner = BrowserWebExtensionReconciliationPlanner()
        let oldPath = "/Applications/Bitwarden.app/Contents/PlugIns/safari.appex"
        let newPath = "/Applications/Bitwarden Beta.app/Contents/PlugIns/safari.appex"
        let plan = planner.plan(
            settingsEntries: [
                BrowserWebExtensionEntry(
                    id: "com.bitwarden.desktop.safari",
                    kind: .safariAppExtension,
                    path: newPath,
                    enabled: true
                ),
            ],
            environmentPaths: [],
            loadedEntries: [
                BrowserWebExtensionReconciliationPlanner.LoadedEntry(
                    id: "com.bitwarden.desktop.safari",
                    standardizedPath: BrowserWebExtensionReconciliationPlanner.standardizedPath(oldPath)
                ),
            ]
        )

        #expect(plan.unloadEntryIDs == ["com.bitwarden.desktop.safari"])
        #expect(plan.unloadEntries == [
            BrowserWebExtensionReconciliationPlanner.UnloadEntry(
                id: "com.bitwarden.desktop.safari",
                preservePermissionState: false
            ),
        ])
        #expect(plan.loadEntries.map(\.path) == [newPath])
    }

    @Test
    func reconciliationPreservesPermissionStateWhenConfiguredEntryIsDisabled() {
        let planner = BrowserWebExtensionReconciliationPlanner()
        let appexPath = "/Applications/Bitwarden.app/Contents/PlugIns/safari.appex"
        let resourcePath = BrowserWebExtensionReconciliationPlanner.standardizedResourceRootPath(
            for: BrowserWebExtensionEntry(
                id: "com.bitwarden.desktop.safari",
                kind: .safariAppExtension,
                path: appexPath,
                enabled: true
            )
        )
        let plan = planner.plan(
            settingsEntries: [
                BrowserWebExtensionEntry(
                    id: "com.bitwarden.desktop.safari",
                    kind: .safariAppExtension,
                    path: appexPath,
                    enabled: false
                ),
            ],
            environmentPaths: [],
            loadedEntries: [
                BrowserWebExtensionReconciliationPlanner.LoadedEntry(
                    id: "com.bitwarden.desktop.safari",
                    standardizedPath: resourcePath
                ),
            ]
        )

        #expect(plan.unloadEntries == [
            BrowserWebExtensionReconciliationPlanner.UnloadEntry(
                id: "com.bitwarden.desktop.safari",
                preservePermissionState: true
            ),
        ])
        #expect(plan.loadEntries.isEmpty)
    }

    @Test
    func failedUnloadRollbackRestoresTheLoadedEntryAsEnabled() {
        let planner = BrowserWebExtensionReconciliationPlanner()
        let loadedEntry = BrowserWebExtensionEntry(
            id: "com.example.extension",
            kind: .safariAppExtension,
            path: "/Applications/Example.app/Contents/PlugIns/Example.appex",
            enabled: true,
            displayName: "Example"
        )

        let restored = planner.rollbackEntriesAfterFailedUnloads(
            settingsEntries: [],
            failedEntries: [loadedEntry]
        )

        #expect(restored == [loadedEntry])
    }
}
