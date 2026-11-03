import Foundation
import MacCleanCore

struct SavedCleanup: Codable, Sendable {
    let items: [CleanupItem]
    let skipped: [String]
    let index: [String: StorageScan]
}

struct SavedApps: Codable, Sendable {
    let items: [AppFootprint]
    let index: [String: StorageScan]
}

struct SavedDuplicates: Codable, Sendable {
    let scan: StorageScan
    let groups: [DuplicateGroup]
    let digests: [String: FileDigest]
}

struct SavedScans: Sendable {
    static let storageKey = "storage-v1"
    static let cleanupKey = "cleanup-v1"
    static let appsKey = "apps-v1"
    static let duplicatesKey = "duplicates-v1"

    let storage: StorageScan?
    let cleanup: SavedCleanup?
    let apps: SavedApps?
    let duplicates: SavedDuplicates?

    init(store: SnapshotStore) {
        // Each page is independent so a missing or unreadable cache never blocks the other pages.
        storage = try? store.read(StorageScan.self, key: Self.storageKey)
        cleanup = try? store.read(SavedCleanup.self, key: Self.cleanupKey)
        apps = try? store.read(SavedApps.self, key: Self.appsKey)
        duplicates = try? store.read(SavedDuplicates.self, key: Self.duplicatesKey)
    }
}
