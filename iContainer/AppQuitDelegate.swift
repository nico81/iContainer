import AppKit

@MainActor
final class AppQuitDelegate: NSObject, NSApplicationDelegate {
    weak var serviceManager: ServiceManager?
    private var isCompletingTermination = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isCompletingTermination else {
            return .terminateNow
        }

        guard let serviceManager, serviceManager.isServiceRunning else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Apple Container System Service is running"
        alert.informativeText = "Vuoi fermare il servizio container prima di chiudere iContainer?"
        alert.addButton(withTitle: "Stop Service and Quit")
        alert.addButton(withTitle: "Quit and Leave Running")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            isCompletingTermination = true
            Task {
                await serviceManager.stopService()
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        case .alertSecondButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }
}
