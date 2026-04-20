import XCTest
@testable import MeetingCaptionTranslator

final class OverlayInteractionConfigurationTests: XCTestCase {
    func test_click_through_configuration_ignores_mouse_and_disables_dragging() {
        let configuration = OverlayInteractionConfiguration.make(isClickThroughEnabled: true)

        XCTAssertTrue(configuration.ignoresMouseEvents)
        XCTAssertFalse(configuration.isMovableByWindowBackground)
    }

    func test_interactive_configuration_receives_mouse_and_allows_dragging() {
        let configuration = OverlayInteractionConfiguration.make(isClickThroughEnabled: false)

        XCTAssertFalse(configuration.ignoresMouseEvents)
        XCTAssertTrue(configuration.isMovableByWindowBackground)
    }
}
