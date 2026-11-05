import Foundation
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testExcludesOnlyReproducibleDirectoriesWithoutRemovingFiles() throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? manager.removeItem(at: root) }
    let documents = root.appendingPathComponent("Documents")
    let support = root.appendingPathComponent("Library/Application Support")
    let paths = [
      "Documents/models/model.onnx", "Documents/templates/details.png",
      "Library/Application Support/content/objects/chart.json",
      "Documents/scores/proof.jpg", "Documents/ddr_database.db",
      "Library/Preferences/settings.plist",
    ]
    for path in paths {
      let file = root.appendingPathComponent(path)
      try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(path.utf8).write(to: file)
    }

    // Existing installations and repeated launches must retain their files.
    BackupExclusions.apply(documents: documents, applicationSupport: support)
    BackupExclusions.apply(documents: documents, applicationSupport: support)

    for path in ["Documents/models", "Documents/templates", "Library/Application Support/content"] {
      let values = try root.appendingPathComponent(path).resourceValues(forKeys: [.isExcludedFromBackupKey])
      XCTAssertEqual(values.isExcludedFromBackup, true, path)
    }
    for path in ["Documents", "Documents/scores", "Library", "Library/Preferences", "Library/Application Support"] {
      let values = try root.appendingPathComponent(path).resourceValues(forKeys: [.isExcludedFromBackupKey])
      XCTAssertNotEqual(values.isExcludedFromBackup, true, path)
    }
    for path in paths {
      XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(path)), Data(path.utf8))
    }
  }

  func testCreatesExcludedDirectoriesBeforeTheirFirstDownload() throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? manager.removeItem(at: root) }
    BackupExclusions.apply(
      documents: root.appendingPathComponent("Documents"),
      applicationSupport: root.appendingPathComponent("Library/Application Support")
    )
    for path in ["Documents/models", "Documents/templates", "Library/Application Support/content"] {
      let directory = root.appendingPathComponent(path)
      XCTAssertEqual(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
      let downloaded = directory.appendingPathComponent("new-download")
      try Data("offline".utf8).write(to: downloaded)
      XCTAssertEqual(try Data(contentsOf: downloaded), Data("offline".utf8))
      XCTAssertEqual(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }
  }
}
