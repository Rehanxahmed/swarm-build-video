// An empty app. UI tests need a host target; the flow drives the real app by
// its bundle id instead (see Flow/SwarmDemo.swift).
import SwiftUI

@main
struct FlowHost: App {
    var body: some Scene { WindowGroup { Color.clear } }
}
