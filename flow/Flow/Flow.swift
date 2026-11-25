// The flow the Demo film plays. Replace the body of testFlow with the real
// steps. Find elements by their text or accessibility identifier:
//     app.buttons["Start workout"], app.staticTexts["Water"], app.textFields["Name"]
// See reference/demo.md for pacing and captions.
import XCTest

final class Flow: XCTestCase {
    func testFlow() throws {
        let app = SwarmDemo.start()
        SwarmDemo.pause(0.8)

        SwarmDemo.caption("Say what this part of the flow shows")
        app.buttons["Example"].tapWhenReady()
        SwarmDemo.pause()

        SwarmDemo.end()
    }
}
