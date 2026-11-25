// Helpers for a Demo film's flow. Don't edit; write the flow in Flow.swift.
//
// record_flow.py launches the app with -swarm-touches, runs this test, waits
// for `start()` to say the app is up front, starts recording, then cues the
// flow. Captions are timed from the cue and written to $SWARM_LOG, which
// render.py reads to show them under the phone.
//
// Run by hand (Xcode, or xcodebuild test) with no SWARM_APP set and it
// launches the app itself, so you can try a flow without recording it.
import XCTest

enum SwarmDemo {
    private static var t0 = Date()
    private static var captions: [[String: Any]] = []
    private static var env: [String: String] { ProcessInfo.processInfo.environment }

    /// Brings the app up front and waits for the recorder's cue.
    static func start(bundleId fallback: String = "") -> XCUIApplication {
        let id = env["SWARM_APP"] ?? fallback
        precondition(!id.isEmpty, "Set SWARM_APP, or pass the app's bundle id to start(bundleId:)")
        let app = XCUIApplication(bundleIdentifier: id)
        if env["SWARM_APP"] == nil {
            app.launchArguments = ["-swarm-touches"]
            app.launch()                          // trying it out: no recorder
        } else {
            app.activate()                        // already launched by the recorder
        }
        _ = app.wait(for: .runningForeground, timeout: 30)
        Thread.sleep(forTimeInterval: 0.6)
        if env["SWARM_APP"] != nil {
            post("swarm.ready")
            let go = XCTDarwinNotificationExpectation(notificationName: "swarm.go")
            _ = XCTWaiter().wait(for: [go], timeout: 180)
        }
        t0 = Date()
        write(end: nil)
        return app
    }

    /// Shows a one-line caption under the phone from now until the next one.
    static func caption(_ text: String) {
        captions.append(["at": Date().timeIntervalSince(t0), "text": text])
        write(end: nil)
    }

    /// Lets the viewer take in what just happened.
    static func pause(_ seconds: Double = 0.8) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// The flow is over; the film holds the last screen.
    static func end() {
        write(end: Date().timeIntervalSince(t0))
    }

    private static func write(end: Double?) {
        guard let path = env["SWARM_LOG"] else { return }
        var log: [String: Any] = ["captions": captions]
        if let end { log["end"] = end }
        if let data = try? JSONSerialization.data(withJSONObject: log, options: [.prettyPrinted]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    private static func post(_ name: String) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(name as CFString), nil, nil, true)
    }
}

extension XCUIElement {
    /// Waits for the element (up to 10 s), then taps it.
    func tapWhenReady(timeout: Double = 10) {
        XCTAssertTrue(waitForExistence(timeout: timeout), "\(self) never appeared")
        tap()
    }
}
