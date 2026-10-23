import AppKit

@main
@MainActor
enum MenuBarStudioMain {
    static func main() {
        let application = NSApplication.shared
        let controller = AppController()
        application.delegate = controller
        application.run()
        withExtendedLifetime(controller) {}
    }
}
