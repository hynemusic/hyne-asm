import XCTest
@testable import HMLauncherCore

final class OnboardingTests: XCTestCase {
    func testShowsOnlyForNewUsers() {
        XCTAssertTrue(Onboarding.showOnLaunch(configExisted: false, done: false))
        XCTAssertFalse(Onboarding.showOnLaunch(configExisted: true, done: false))
        XCTAssertFalse(Onboarding.showOnLaunch(configExisted: false, done: true))
    }

    func testStepDoneFollowsStatus() {
        var s = OnboardingStatus()
        XCTAssertEqual(OnboardingStep.allCases.filter(s.isDone), [.welcome])
        s.connected = true
        XCTAssertTrue(s.isDone(.connect))
        s.permission = true
        XCTAssertTrue(s.isDone(.permission))
        s.menuChosen = true
        XCTAssertTrue(s.isDone(.menu))
        XCTAssertFalse(s.isDone(.tryIt))
        s.panelOpened = true
        XCTAssertTrue(s.isDone(.tryIt))
    }

    func testStarterSetAddsKnownDevicesOnce() {
        var c = LauncherConfig.makeDefault()   // Favorites, Instruments, Effects
        let items = [item("EQ Eight", uri: "eq", source: .audioEffects),
                     item("Reverb", uri: "rv", source: .audioEffects),
                     item("Drift", uri: "dr", source: .instruments),
                     item("Serum", uri: "se")]
        XCTAssertEqual(c.addStarterSet(from: items), 3)
        XCTAssertEqual(c.categories[2].entries.map(\.title), ["EQ Eight", "Reverb"])
        XCTAssertEqual(c.categories[1].entries.map(\.title), ["Drift"])
        XCTAssertEqual(c.addStarterSet(from: items), 0)
        XCTAssertEqual(c.categories[2].entries.count, 2)
        XCTAssertEqual(c.categories[1].entries.count, 1)
    }

    func testOnboardingDoneDecodesDefault() throws {
        let old = #"{"version": 4, "categories": []}"#.data(using: .utf8)!
        XCTAssertFalse(try JSONDecoder().decode(LauncherConfig.self, from: old).onboardingDone)
        var c = LauncherConfig.makeDefault()
        c.onboardingDone = true
        XCTAssertTrue(try JSONDecoder().decode(LauncherConfig.self, from: JSONEncoder().encode(c)).onboardingDone)
    }
}
