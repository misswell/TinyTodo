import AppKit
import XCTest
@testable import TinyTodo

/// Guards the panel's single content rail.
///
/// Before 1.3.1 every band carried its own number, so the day labels sat at 8pt, the header
/// and quick input at 14pt and the rows at 26pt. These assertions keep the derived metrics
/// consistent so a future tweak cannot silently reintroduce the misalignment.
final class PanelLayoutTests: XCTestCase {
    func testTextColumnSitsAfterTheGlyphColumn() {
        XCTAssertEqual(
            PanelLayout.textInset,
            PanelLayout.contentInset + PanelLayout.glyphWidth + PanelLayout.glyphTextGap
        )
    }

    func testRowInsetsPutTheGlyphExactlyOnTheContentRail() {
        // The list adds its own margin; the inset compensates for it, so glyph + margin must
        // land on the rail the header and tab bar use.
        XCTAssertEqual(
            PanelLayout.listLeadingMargin + PanelLayout.rowInsetLeading,
            PanelLayout.contentInset,
            accuracy: 0.001
        )
        XCTAssertEqual(
            PanelLayout.listTrailingMargin + PanelLayout.rowInsetTrailing,
            PanelLayout.contentInset,
            accuracy: 0.001
        )
    }

    func testGroupLabelSeparatesMoreAboveThanBelow() {
        XCTAssertGreaterThan(
            PanelLayout.sectionTopPadding,
            PanelLayout.sectionBottomPadding,
            "a group label must belong to the rows under it, not float between groups"
        )
    }

    func testRailFitsInsideTheNarrowestPanel() {
        // The panel can be dragged down to 300pt wide; the text column must still clear the
        // leading rail with room to spare for a readable line.
        let available = AppInfo.minimumPanelSize.width - PanelLayout.textInset - PanelLayout.contentInset
        XCTAssertGreaterThan(available, 200)
    }
}