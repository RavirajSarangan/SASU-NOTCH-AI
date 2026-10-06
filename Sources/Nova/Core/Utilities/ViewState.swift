import SwiftUI

/// The macOS 26 SDK declares a `@State` *macro* that shadows the property
/// wrapper, and its plugin ships only with Xcode. Using the wrapper through a
/// typealias keeps the project buildable with the Command Line Tools alone.
/// Behaves exactly like `@State`.
typealias ViewState = SwiftUI.State
