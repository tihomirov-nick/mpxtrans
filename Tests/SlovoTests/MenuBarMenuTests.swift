import XCTest
import AppKit
import TransCore
@testable import Slovo

/// The menu of the menu bar icon: what to stop, then the tail every app of the family has.
@MainActor
final class MenuBarMenuTests: XCTestCase {
    func testTheMenuIsStopThenSettingsUpdatesAboutAndQuit() {
        let menu = MenuBarIcon(transcriber: Transcriber.shared).makeMenu()
        XCTAssertEqual(menu.items.map { $0.isSeparatorItem ? "-" : $0.title }, [
            L("Остановить распознавание"), "-",
            L("Настройки…"), L("Проверить обновления…"), L("О приложении «Slovo»"), "-",
            L("Завершить Slovo"),
        ])
        // The shortcuts of the app's own menu, shown here for the same actions.
        XCTAssertEqual(menu.items[2].keyEquivalent, ",")
        XCTAssertEqual(menu.items[2].keyEquivalentModifierMask, .command)
        XCTAssertEqual(menu.items[6].keyEquivalent, "q")
        XCTAssertEqual(menu.items[6].keyEquivalentModifierMask, .command)
    }

    func testThereIsNothingToStopWhenNothingRuns() {
        let transcriber = Transcriber.shared
        XCTAssertNotEqual(transcriber.phase, .working)
        let menu = MenuBarIcon(transcriber: transcriber).makeMenu()
        XCTAssertFalse(menu.items[0].isEnabled)
        for index in [2, 4, 6] { XCTAssertTrue(menu.items[index].isEnabled, menu.items[index].title) }
    }
}
