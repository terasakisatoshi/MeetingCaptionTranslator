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

        let sourceRange = (document.string as NSString).range(of: "hello world")
        let translatedRange = (document.string as NSString).range(of: "こんにちは世界")
        let secondRange = (document.string as NSString).range(of: "how are you")
        let sourceFont = document.attribute(.font, at: sourceRange.location, effectiveRange: nil) as? NSFont
        let translationFont = document.attribute(.font, at: translatedRange.location, effectiveRange: nil) as? NSFont
        XCTAssertEqual(sourceFont?.pointSize, 24)
        XCTAssertEqual(translationFont?.pointSize, sourceFont?.pointSize)
        let sourceStyle = document.attribute(.paragraphStyle, at: sourceRange.location, effectiveRange: nil) as? NSParagraphStyle
        let translationStyle = document.attribute(.paragraphStyle, at: translatedRange.location, effectiveRange: nil) as? NSParagraphStyle
        let secondStyle = document.attribute(.paragraphStyle, at: secondRange.location, effectiveRange: nil) as? NSParagraphStyle
        let sourceCell = sourceStyle?.textBlocks.first as? NSTextTableBlock
        let translationCell = translationStyle?.textBlocks.first as? NSTextTableBlock
        let secondCell = secondStyle?.textBlocks.first as? NSTextTableBlock
        XCTAssertEqual(sourceCell?.startingColumn, 0)
        XCTAssertEqual(translationCell?.startingColumn, 1)
        XCTAssertEqual(sourceCell?.startingRow, translationCell?.startingRow)
        XCTAssertEqual(secondCell?.startingRow, 1)
        XCTAssertEqual(sourceCell?.table.numberOfColumns, 2)
        let storage = NSTextStorage(attributedString: document)
        let layout = NSLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: 800, height: 2000))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        let sourceRect = layout.boundingRect(forGlyphRange: layout.glyphRange(forCharacterRange: sourceRange, actualCharacterRange: nil), in: container)
        let translationRect = layout.boundingRect(forGlyphRange: layout.glyphRange(forCharacterRange: translatedRange, actualCharacterRange: nil), in: container)
        XCTAssertGreaterThan(translationRect.minX, sourceRect.minX + 300)
        XCTAssertEqual(translationRect.minY, sourceRect.minY, accuracy: 5)
    }
}
