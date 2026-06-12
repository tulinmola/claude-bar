import AppKit

let arguments = CommandLine.arguments

if let index = arguments.firstIndex(of: "--preview"), index + 1 < arguments.count {
    renderPreview(to: arguments[index + 1])
    exit(0)
}

// main.swift top-level code runs on the main thread at process start, so it is
// safe to assume main-actor isolation for the AppKit setup.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate   // NSApplication.delegate is weak, so hold a strong
    withExtendedLifetime(delegate) {   // reference across the run loop.
        app.run()
    }
}
