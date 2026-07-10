import AppKit
import Bonsplit
import Foundation

extension DockSplitStore {
    func panel(for tabId: TabID) -> (any Panel)? {
        guard let panelId = surfaceIdToPanelId[tabId] else { return nil }
        return panels[panelId]
    }

    func forEachPanel(_ body: (UUID, any Panel) -> Void) {
        for (panelId, panel) in panels { body(panelId, panel) }
    }

    func browserPanel(for panelId: UUID) -> BrowserPanel? {
        panels[panelId] as? BrowserPanel
    }

    func browserPanel(owning responder: NSResponder?, in window: NSWindow?) -> BrowserPanel? {
        guard let responder, let window else { return nil }
        if let focused = focusedPanelId,
           let browser = panels[focused] as? BrowserPanel,
           browser.ownedFocusIntent(for: responder, in: window) != nil {
            return browser
        }
        for (panelId, panel) in panels {
            guard panelId != focusedPanelId,
                  let browser = panel as? BrowserPanel,
                  browser.ownedFocusIntent(for: responder, in: window) != nil else {
                continue
            }
            return browser
        }
        return nil
    }

    func surfaceId(forPanelId panelId: UUID) -> TabID? {
        surfaceIdToPanelId.first { $0.value == panelId }?.key
    }

    func paneId(forPanelId panelId: UUID) -> PaneID? {
        guard let tabId = surfaceId(forPanelId: panelId) else { return nil }
        for paneId in bonsplitController.allPaneIds
        where bonsplitController.tabs(inPane: paneId).contains(where: { $0.id == tabId }) {
            return paneId
        }
        return nil
    }

    var focusedPanelId: UUID? {
        guard let paneId = bonsplitController.focusedPaneId,
              let tabId = bonsplitController.selectedTab(inPane: paneId)?.id else { return nil }
        return surfaceIdToPanelId[tabId]
    }
}
