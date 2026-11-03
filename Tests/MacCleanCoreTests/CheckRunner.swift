import Foundation
import Darwin

var failureCount = 0
class TestCase {
    func setUpWithError() throws {}
    func tearDownWithError() throws {}
}
struct XCTSkip: Error { let message: String; init(_ message: String) { self.message = message } }
func fail(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
    failureCount += 1; print("FAIL \(file):\(line): \(message)")
}
func XCTAssertTrue(_ value: @autoclosure () throws -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) rethrows {
    if try !value() { fail("Expected true. " + message, file: file, line: line) }
}
func XCTAssertFalse(_ value: @autoclosure () throws -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) rethrows {
    if try value() { fail("Expected false. " + message, file: file, line: line) }
}
func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) rethrows {
    let left = try a(), right = try b(); if left != right { fail("\(left) != \(right)", file: file, line: line) }
}
func XCTAssertGreaterThan<T: Comparable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) {
    if !(a > b) { fail("Expected \(a) > \(b)", file: file, line: line) }
}
func XCTAssertNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) {
    if value != nil { fail("Expected nil", file: file, line: line) }
}
func XCTAssertNotNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) {
    if value == nil { fail("Unexpected nil", file: file, line: line) }
}
func XCTUnwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw NSError(domain: "MacCleanChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unexpected nil"]) }; return value
}
func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line, _ handler: (Error) -> Void = { _ in }) {
    do { _ = try expression(); fail("Expected an error. " + message, file: file, line: line) } catch { handler(error) }
}

@main struct CheckRunner {
    static func main() {
        let suite = CoreTests()
        let checks: [(String, () throws -> Void)] = [
            ("testNestedTotalsAndHiddenFiles", suite.testNestedTotalsAndHiddenFiles),
            ("testSymlinksAreNotFollowed", suite.testSymlinksAreNotFollowed),
            ("testHardLinksAreCountedOnce", suite.testHardLinksAreCountedOnce),
            ("testCancellation", suite.testCancellation),
            ("testMissingRootFails", suite.testMissingRootFails),
            ("testDuplicateContentRatherThanName", suite.testDuplicateContentRatherThanName),
            ("testDuplicateChangedFileIsExcluded", suite.testDuplicateChangedFileIsExcluded),
            ("testSHA256KnownVector", suite.testSHA256KnownVector),
            ("testCleanupAgeAndManualCategories", suite.testCleanupAgeAndManualCategories),
            ("testRecentChildPreventsOldCacheRecommendation", suite.testRecentChildPreventsOldCacheRecommendation),
            ("testRunningAppCacheIsSkipped", suite.testRunningAppCacheIsSkipped),
            ("testProtectedPaths", suite.testProtectedPaths),
            ("testChangedIdentityAndContentAreRejected", suite.testChangedIdentityAndContentAreRejected),
            ("testSymlinkParentIsRejected", suite.testSymlinkParentIsRejected),
            ("testPathBoundariesAndOverlaps", suite.testPathBoundariesAndOverlaps),
            ("testAppFootprintExactMatches", suite.testAppFootprintExactMatches),
            ("testCorruptHistoryBlocksCleanup", suite.testCorruptHistoryBlocksCleanup),
            ("testTrashAndRestoreIntegration", suite.testTrashAndRestoreIntegration),
            ("testChangedDirectoryDescendantsAreRejected", suite.testChangedDirectoryDescendantsAreRejected),
            ("testDuplicateRetainedCopyMustRemainValid", suite.testDuplicateRetainedCopyMustRemainValid),
            ("testCancelledTrashPreservesFiles", suite.testCancelledTrashPreservesFiles),
            ("testIncrementalRemovalKeepsTreeAndUpdatesAncestors", suite.testIncrementalRemovalKeepsTreeAndUpdatesAncestors),
            ("testMoveWithinScopePreservesTrashOccupationAndRestores", suite.testMoveWithinScopePreservesTrashOccupationAndRestores),
            ("testIncrementalDirectoryMoveKeepsNestedNodes", suite.testIncrementalDirectoryMoveKeepsNestedNodes),
            ("testIncrementalHardLinkReassignsAllocation", suite.testIncrementalHardLinkReassignsAllocation),
            ("testIncrementalUpdateDoesNotRescanUnrelatedFiles", suite.testIncrementalUpdateDoesNotRescanUnrelatedFiles),
            ("testDuplicateGroupsRemainAfterPartialCleanup", suite.testDuplicateGroupsRemainAfterPartialCleanup),
            ("testAppAndCleanupRemainUsableAfterRelatedRemoval", suite.testAppAndCleanupRemainUsableAfterRelatedRemoval),
            ("testDuplicateTrashCopiesAreExcluded", suite.testDuplicateTrashCopiesAreExcluded),
            ("testSavedStorageIncrementalRefreshMatchesFreshScan", suite.testSavedStorageIncrementalRefreshMatchesFreshScan),
            ("testDuplicateRefreshReusesHashesAndChecksChangedContent", suite.testDuplicateRefreshReusesHashesAndChecksChangedContent),
            ("testPreviousScanDoesNotFollowReplacedDirectorySymlink", suite.testPreviousScanDoesNotFollowReplacedDirectorySymlink)
        ]
        var skipped = 0
        for (name, check) in checks {
            let before = failureCount
            do {
                try suite.setUpWithError(); try check()
                print(failureCount == before ? "PASS \(name)" : "FAIL \(name)")
            } catch let error as XCTSkip { skipped += 1; print("SKIP \(name): \(error.message)") }
            catch { fail("\(name): \(error.localizedDescription)") }
            do { try suite.tearDownWithError() } catch { fail("Fixture teardown: \(error)") }
        }
        print("\(checks.count) checks, \(skipped) skipped, \(failureCount) failures")
        exit(failureCount == 0 ? 0 : 1)
    }
}
