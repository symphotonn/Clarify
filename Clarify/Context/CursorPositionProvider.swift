import AppKit

enum CursorPositionProvider {
    /// Returns the best anchor point for the overlay panel in AppKit coordinates.
    static func anchorPoint(from context: ContextInfo) -> CGPoint {
        if let bounds = context.selectionBounds {
            // AX coordinates: origin at top-left of main screen
            // Place panel below the selection
            let axPoint = CGPoint(
                x: bounds.origin.x,
                y: bounds.origin.y + bounds.height + Constants.panelAnchorOffset
            )
            return NSScreen.convertFromAX(axPoint)
        }

        return mouseLocation()
    }

    /// Fallback: use current mouse position.
    static func mouseLocation() -> CGPoint {
        NSEvent.mouseLocation
    }
}
