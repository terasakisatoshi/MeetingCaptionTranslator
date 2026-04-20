import AppKit
import XCTest
@testable import MeetingCaptionTranslator

@MainActor
final class SelectableMessageTextTests: XCTestCase {
    func test_make_createsSelectableWrappingLabel() {
        let textField = SelectableMessageTextField.make(
            text: "Core Audio failed to start io",
            textColor: NSColor.systemRed,
            font: NSFont.systemFont(ofSize: 13)
        )

        XCTAssertEqual(textField.stringValue, "Core Audio failed to start io")
        XCTAssertTrue(textField.isSelectable)
        XCTAssertFalse(textField.isEditable)
        XCTAssertFalse(textField.isBordered)
        XCTAssertFalse(textField.drawsBackground)
        XCTAssertFalse(textField.usesSingleLineMode)
        XCTAssertEqual(textField.maximumNumberOfLines, 0)
        XCTAssertEqual(textField.lineBreakMode, NSLineBreakMode.byWordWrapping)
        XCTAssertEqual(textField.textColor, NSColor.systemRed)
    }

    func test_configure_updatesExistingLabelContents() {
        let textField = NSTextField(labelWithString: "before")

        SelectableMessageTextField.configure(
            textField,
            text: "after",
            textColor: NSColor.labelColor,
            font: NSFont.systemFont(ofSize: 12)
        )

        XCTAssertEqual(textField.stringValue, "after")
        XCTAssertTrue(textField.isSelectable)
        XCTAssertFalse(textField.isEditable)
    }
}
