import XCTest
@testable import MeetingCaptionTranslator

@MainActor
final class OverlayInteractionConfigurationTests: XCTestCase {
    func test_default_configuration_receives_mouse_and_allows_dragging() {
        let configuration = OverlayInteractionConfiguration.defaultConfiguration

        XCTAssertFalse(configuration.ignoresMouseEvents)
        XCTAssertTrue(configuration.isMovableByWindowBackground)
    }

    func test_drag_strip_creates_window_movable_view() {
        let view = OverlayWindowDragStripComponents.make()

        XCTAssertTrue(view.mouseDownCanMoveWindow)
    }

    func test_default_chrome_uses_titled_full_size_resizable_window() {
        let configuration = OverlayWindowChromeConfiguration.defaultConfiguration

        XCTAssertTrue(configuration.styleMask.contains(.titled))
        XCTAssertTrue(configuration.styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(configuration.styleMask.contains(.resizable))
    }

    func test_default_chrome_hides_titlebar_text_and_buttons() {
        let configuration = OverlayWindowChromeConfiguration.defaultConfiguration

        XCTAssertEqual(configuration.titleVisibility, .hidden)
        XCTAssertTrue(configuration.titlebarAppearsTransparent)
        XCTAssertTrue(configuration.hidesStandardWindowButtons)
    }
}
