import XCTest
@testable import Mobidex

final class ProjectListProjectionTests: XCTestCase {
    func testMacOSPrivacyWarningFlagsProtectedUserFolders() throws {
        XCTAssertNil(ProjectRecord(path: "/Users/yesh/Code/app").macOSPrivacyWarning)
        XCTAssertNotNil(ProjectRecord(path: "/Users/yesh/Documents/work/app").macOSPrivacyWarning)
        XCTAssertNotNil(ProjectRecord(path: "/Users/yesh/Library/Mobile Documents/com~apple~CloudDocs/app").macOSPrivacyWarning)
        XCTAssertNotNil(ProjectRecord(path: "/Volumes/External/app").macOSPrivacyWarning)
        XCTAssertNotNil(ProjectRecord(path: "/Users/yesh/Code/app", sessionPaths: ["/Users/yesh/Desktop/app"]).macOSPrivacyWarning)
    }

    func testSeparatesFavoritesFromActiveDiscoveredProjects() throws {
        let favoriteWithoutChats = ProjectRecord(path: "/srv/favorite", discovered: false, isFavorite: true)
        let activeDiscovered = ProjectRecord(path: "/srv/active", discovered: true, discoveredSessionCount: 2)
        let inactiveDiscovered = ProjectRecord(path: "/srv/inactive", discovered: true)

        let sections = ProjectListSections(
            projects: [inactiveDiscovered, activeDiscovered, favoriteWithoutChats],
            searchText: "",
            showInactiveDiscoveredProjects: false,
            showArchivedSessionProjects: false
        )

        XCTAssertEqual(sections.favorites.map(\.path), ["/srv/favorite"])
        XCTAssertEqual(sections.discovered.map(\.path), ["/srv/active"])
        XCTAssertTrue(sections.showInactiveDiscoveredFilter)
        XCTAssertEqual(sections.discoveredTitle, "Discovered")
    }

    func testCanIncludeInactiveDiscoveredProjects() throws {
        let activeDiscovered = ProjectRecord(path: "/srv/active", discovered: true, discoveredSessionCount: 2)
        let inactiveDiscovered = ProjectRecord(path: "/srv/inactive", discovered: true)

        let sections = ProjectListSections(
            projects: [inactiveDiscovered, activeDiscovered],
            searchText: "",
            showInactiveDiscoveredProjects: true,
            showArchivedSessionProjects: false
        )

        XCTAssertEqual(sections.discovered.map(\.path), ["/srv/active", "/srv/inactive"])
        XCTAssertEqual(sections.discoveredTitle, "Discovered")
    }

    func testSearchFindsInactiveDiscoveredProjects() throws {
        let activeDiscovered = ProjectRecord(path: "/srv/active", discovered: true, discoveredSessionCount: 2)
        let inactiveDiscovered = ProjectRecord(path: "/srv/inactive-match", displayName: "inactive-match", discovered: true)

        let sections = ProjectListSections(
            projects: [activeDiscovered, inactiveDiscovered],
            searchText: "match",
            showInactiveDiscoveredProjects: false,
            showArchivedSessionProjects: false
        )

        XCTAssertTrue(sections.favorites.isEmpty)
        XCTAssertEqual(sections.discovered.map(\.path), ["/srv/inactive-match"])
        XCTAssertEqual(sections.discoveredTitle, "Discovered")
    }

    func testKeepsManualProjectsVisibleAndSearchable() throws {
        let manualProject = ProjectRecord(path: "/srv/manual", discovered: false)
        let activeDiscovered = ProjectRecord(path: "/srv/active", discovered: true, discoveredSessionCount: 2)

        let defaultSections = ProjectListSections(
            projects: [manualProject, activeDiscovered],
            searchText: "",
            showInactiveDiscoveredProjects: false,
            showArchivedSessionProjects: false
        )
        XCTAssertEqual(defaultSections.favorites.map(\.path), ["/srv/manual"])
        XCTAssertTrue(defaultSections.added.isEmpty)

        let searchSections = ProjectListSections(
            projects: [manualProject, activeDiscovered],
            searchText: "manual",
            showInactiveDiscoveredProjects: false,
            showArchivedSessionProjects: false
        )
        XCTAssertEqual(searchSections.favorites.map(\.path), ["/srv/manual"])
        XCTAssertTrue(searchSections.added.isEmpty)
        XCTAssertTrue(searchSections.discovered.isEmpty)
    }

    func testArchivedSessionProjectsStayHiddenUntilRequested() throws {
        let archived = ProjectRecord(path: "/srv/archive", discovered: true, archivedSessionCount: 4)
        let active = ProjectRecord(path: "/srv/active", discovered: true, discoveredSessionCount: 1)

        let hidden = ProjectListSections(
            projects: [archived, active],
            searchText: "",
            showInactiveDiscoveredProjects: false,
            showArchivedSessionProjects: false
        )
        XCTAssertEqual(hidden.discovered.map(\.path), ["/srv/active"])
        XCTAssertTrue(hidden.showArchivedSessionFilter)

        let shown = ProjectListSections(
            projects: [archived, active],
            searchText: "",
            showInactiveDiscoveredProjects: false,
            showArchivedSessionProjects: true
        )
        XCTAssertEqual(shown.discovered.map(\.path), ["/srv/active", "/srv/archive"])
    }

    func testSearchDoesNotRevealArchivedOnlyProjectsUntilRequested() throws {
        let archived = ProjectRecord(path: "/srv/archive-match", displayName: "archive-match", discovered: true, archivedSessionCount: 4)
        let inactive = ProjectRecord(path: "/srv/inactive-match", displayName: "inactive-match", discovered: true)

        let hidden = ProjectListSections(
            projects: [archived, inactive],
            searchText: "match",
            showInactiveDiscoveredProjects: false,
            showArchivedSessionProjects: false
        )
        XCTAssertEqual(hidden.discovered.map(\.path), ["/srv/inactive-match"])

        let shown = ProjectListSections(
            projects: [archived, inactive],
            searchText: "match",
            showInactiveDiscoveredProjects: false,
            showArchivedSessionProjects: true
        )
        XCTAssertEqual(shown.discovered.map(\.path), ["/srv/archive-match", "/srv/inactive-match"])
    }
}
