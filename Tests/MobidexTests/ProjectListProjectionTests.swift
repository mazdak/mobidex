import XCTest
@testable import Mobidex

final class ProjectListProjectionTests: XCTestCase {
    func testSeparatesFavoritesFromActiveDiscoveredProjects() throws {
        let favoriteWithoutChats = ProjectRecord(path: "/srv/favorite", discovered: false, isFavorite: true)
        let activeDiscovered = ProjectRecord(path: "/srv/active", discovered: true, discoveredSessionCount: 2)
        let inactiveDiscovered = ProjectRecord(path: "/srv/inactive", discovered: true)

        let sections = ProjectListSections(
            projects: [inactiveDiscovered, activeDiscovered, favoriteWithoutChats],
            searchText: "",
            showInactiveDiscoveredProjects: false
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
            showInactiveDiscoveredProjects: true
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
            showInactiveDiscoveredProjects: false
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
            showInactiveDiscoveredProjects: false
        )
        XCTAssertEqual(defaultSections.added.map(\.path), ["/srv/manual"])

        let searchSections = ProjectListSections(
            projects: [manualProject, activeDiscovered],
            searchText: "manual",
            showInactiveDiscoveredProjects: false
        )
        XCTAssertEqual(searchSections.added.map(\.path), ["/srv/manual"])
        XCTAssertTrue(searchSections.discovered.isEmpty)
    }
}
