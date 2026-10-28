import AppKit

@main
@MainActor
enum MenuBarStudioMain {
    static func main() {
        let application = NSApplication.shared
        if CommandLine.arguments.contains("--native-probe") {
            let probe = NativeSmokeProbe()
            application.delegate = probe
            application.run()
            withExtendedLifetime(probe) {}
            return
        }
        let controller = AppController()
        application.delegate = controller
        application.run()
        withExtendedLifetime(controller) {}
    }
}
