import AppKit

enum PanelPositioner {
    /// Calculate the panel frame, anchored below the given point, clamped to the visible screen.
    /// Falls back to positioning above if there's not enough room below.
    static func frame(anchorPoint: CGPoint, contentHeight: CGFloat) -> NSRect {
        let width = Constants.panelWidth
        let height = min(contentHeight, Constants.panelMaxHeight)

        let screen = NSScreen.screen(containing: anchorPoint) ?? NSScreen.main ?? NSScreen.screens[0]
        let visibleFrame = screen.visibleFrame

        // Start by centering horizontally on the anchor
        var x = anchorPoint.x - width / 2
        // Position below the anchor (in AppKit coordinates, below means lower y)
        var y = anchorPoint.y - height - Constants.panelAnchorOffset

        // Clamp horizontally
        x = max(visibleFrame.minX + 8, min(x, visibleFrame.maxX - width - 8))

        // If panel would go below the visible area, flip above
        if y < visibleFrame.minY + 8 {
            y = anchorPoint.y + Constants.panelAnchorOffset
        }

        // Clamp vertically
        y = max(visibleFrame.minY + 8, min(y, visibleFrame.maxY - height - 8))

        return NSRect(x: x, y: y, width: width, height: height)
    }
}
