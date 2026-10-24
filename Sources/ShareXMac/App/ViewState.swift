import SwiftUI

// Use the property wrapper on every supported SDK. SDK 27 also exports a
// same-named macro whose plugin is unavailable in Command Line Tools builds.
typealias ViewState<Value> = SwiftUI.State<Value>
