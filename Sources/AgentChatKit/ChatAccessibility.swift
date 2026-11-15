import SwiftUI

extension View {
    /// An absent configuration must not erase an identifier already supplied by a host slot view.
    @ViewBuilder
    func chatIdentifier(_ identifier: String?) -> some View {
        if let identifier { accessibilityIdentifier(identifier) }
        else { self }
    }
}

