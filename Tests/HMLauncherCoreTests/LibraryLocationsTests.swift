import XCTest
@testable import HMLauncherCore

final class LibraryLocationsTests: XCTestCase {
    private let config = """
    <?xml version="1.0" encoding="UTF-8"?>
    <Ableton>
    	<ContentLibrary>
    		<UserLibrary>
    			<LibraryProject Id="0">
    				<ProjectLocation />
    				<ProjectName Value="User Library" />
    				<ProjectPath Value="/Volumes/Audio/Ableton" />
    			</LibraryProject>
    		</UserLibrary>
    		<UserFolderInfoList>
    			<UserFolderInfo Id="1" Path="/Volumes/Audio/Racks" DisplayName="My Racks" IconName="" />
    			<UserFolderInfo Id="2" Path="/Users/me/Presets &amp; More" DisplayName="" IconName="" />
    		</UserFolderInfoList>
    	</ContentLibrary>
    </Ableton>
    """

    func testReadsUserLibraryAndPlaces() {
        let locations = LibraryLocations.parse(libraryConfig: Data(config.utf8))
        XCTAssertEqual(locations, [
            LibraryLocation(kind: .userLibrary, name: "User Library", path: "/Volumes/Audio/Ableton/User Library"),
            LibraryLocation(kind: .place, name: "My Racks", path: "/Volumes/Audio/Racks"),
            LibraryLocation(kind: .place, name: "Presets & More", path: "/Users/me/Presets & More"),
        ])
    }

    func testFallsBackToDefaultUserLibrary() {
        let locations = LibraryLocations.parse(libraryConfig: Data("<Ableton/>".utf8))
        XCTAssertEqual(locations, [LibraryLocation(kind: .userLibrary, name: "User Library", path: PresetImport.userLibraryURL.path)])
    }

    func testPicksRunningVersionThenNewestConfig() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for (folder, age) in [("Live 12.3", 100.0), ("Live 12.4.7", 50.0), ("Live 12.4.8", 10.0)] {
            let dir = root.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent("Library.cfg")
            try Data().write(to: file)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: file.path)
        }
        XCTAssertEqual(LibraryLocations.libraryConfig(liveVersion: "12.4.7", root: root)?.deletingLastPathComponent().lastPathComponent, "Live 12.4.7")
        XCTAssertEqual(LibraryLocations.libraryConfig(liveVersion: "13.0", root: root)?.deletingLastPathComponent().lastPathComponent, "Live 12.4.8")
        XCTAssertEqual(LibraryLocations.libraryConfig(liveVersion: nil, root: root)?.deletingLastPathComponent().lastPathComponent, "Live 12.4.8")
    }

    func testListsSystemAndUserPluginFolders() {
        let paths = LibraryLocations.pluginFolders(home: URL(fileURLWithPath: "/Users/me")).map(\.path)
        XCTAssertTrue(paths.contains("/Library/Audio/Plug-Ins/VST3"))
        XCTAssertTrue(paths.contains("/Users/me/Library/Audio/Plug-Ins/Components"))
    }
}
