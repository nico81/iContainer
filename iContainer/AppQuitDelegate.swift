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

        // Honor the user's quit-behavior preference from Settings when it
        // is set to anything other than `.ask`, so we don't pop the
        // confirmation dialog on every quit.
        switch SettingsManager.storedQuitBehavior() {
        case .leaveRunning:
            return .terminateNow
        case .stopService:
            isCompletingTermination = true
            Task {
                await serviceManager.stopService()
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        case .ask:
            break
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Apple container service is running"
        alert.informativeText = "Do you want to stop the container service before quitting iContainer?"
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
