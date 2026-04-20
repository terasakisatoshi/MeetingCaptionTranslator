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

    func test_make_scrollable_text_view_creates_selectable_scrolling_text_view() {
        let scrollView = OverlayTranscriptTextViewComponents.make()
        let textView = try? XCTUnwrap(scrollView.documentView as? NSTextView)

        XCTAssertNotNil(textView)
        XCTAssertTrue(scrollView.hasVerticalScroller)
        XCTAssertFalse(scrollView.drawsBackground)
        XCTAssertEqual(scrollView.borderType, .noBorder)
        XCTAssertTrue(textView?.isSelectable == true)
        XCTAssertFalse(textView?.isEditable == true)
        XCTAssertFalse(textView?.drawsBackground == true)
    }

    func test_overlay_transcript_document_builds_single_copyable_block() {
        let rows = [
            OverlayRow(
                id: UUID(),
                sourceText: "hello world",
                translatedText: "こんにちは世界",
                state: .final
            ),
            OverlayRow(
                id: UUID(),
                sourceText: "how are you",
                translatedText: nil,
                state: .partial
            )
        ]

        let document = OverlayTranscriptDocument.make(
            rows: rows,
            fontSize: 24,
            statusText: "Capturing"
        )

        XCTAssertEqual(
            document.string,
            """
            hello world
            こんにちは世界

            how are you
            """
        )
    }
}
