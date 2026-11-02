import Foundation
import Testing
@testable import Rackside

private func makeStoreDir() throws -> URL {
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appending(path: "store-backup-test-\(UUID().uuidString)")
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

@Test func backupOnVersionChangeAndRestore() throws {
    let fm = FileManager.default
    let dir = try makeStoreDir()
    defer { try? fm.removeItem(at: dir) }

    let storeURL = dir.appending(path: "default.store")
    try Data("v1-data".utf8).write(to: storeURL)
    let defaults = UserDefaults(suiteName: "StoreBackupTests-\(UUID().uuidString)")!

    // First run records the version without creating a backup.
    try StoreBackup.backupIfVersionChanged(storeURL: storeURL, currentVersion: "1.0", defaults: defaults)
    #expect(!fm.fileExists(atPath: dir.appending(path: "Backups").path))

    // Same version again: still no backup.
    try StoreBackup.backupIfVersionChanged(storeURL: storeURL, currentVersion: "1.0", defaults: defaults)
    #expect(!fm.fileExists(atPath: dir.appending(path: "Backups").path))

    // Version change: backup created.
    try StoreBackup.backupIfVersionChanged(storeURL: storeURL, currentVersion: "1.1", defaults: defaults)
    #expect(fm.fileExists(atPath: dir.appending(path: "Backups/pre-schema-1.1/default.store").path))

    // Corrupt the store, then restore returns the backed-up bytes.
    try Data("corrupt".utf8).write(to: storeURL)
    try StoreBackup.restoreLatest(storeURL: storeURL)
    #expect(try String(contentsOf: storeURL, encoding: .utf8) == "v1-data")
}

@Test func restoreRemovesLiveWALNotPresentInBackup() throws {
    let fm = FileManager.default
    let dir = try makeStoreDir()
    defer { try? fm.removeItem(at: dir) }

    let storeURL = dir.appending(path: "default.store")
    let walURL = dir.appending(path: "default.store-wal")
    let shmURL = dir.appending(path: "default.store-shm")
    try Data("v1-data".utf8).write(to: storeURL)
    let defaults = UserDefaults(suiteName: "StoreBackupTests-\(UUID().uuidString)")!

    // Backup taken while the store had no WAL (clean checkpoint).
    try StoreBackup.backupIfVersionChanged(storeURL: storeURL, currentVersion: "1.0", defaults: defaults)
    try StoreBackup.backupIfVersionChanged(storeURL: storeURL, currentVersion: "1.1", defaults: defaults)

    // The failed open leaves a WAL and SHM behind that belong to the broken store.
    try Data("stale-wal".utf8).write(to: walURL)
    try Data("stale-shm".utf8).write(to: shmURL)
    try Data("corrupt".utf8).write(to: storeURL)

    try StoreBackup.restoreLatest(storeURL: storeURL)

    #expect(try String(contentsOf: storeURL, encoding: .utf8) == "v1-data")
    #expect(!fm.fileExists(atPath: walURL.path))
    #expect(!fm.fileExists(atPath: shmURL.path))
}

@Test func failedBackupDoesNotRecordVersion() throws {
    let fm = FileManager.default
    let dir = try makeStoreDir()
    defer { try? fm.removeItem(at: dir) }

    let storeURL = dir.appending(path: "default.store")
    try Data("v1-data".utf8).write(to: storeURL)
    let defaults = UserDefaults(suiteName: "StoreBackupTests-\(UUID().uuidString)")!
    try StoreBackup.backupIfVersionChanged(storeURL: storeURL, currentVersion: "1.0", defaults: defaults)

    // An unreadable store makes the backup copy fail.
    try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: storeURL.path)
    defer { try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: storeURL.path) }

    #expect(throws: (any Error).self) {
        try StoreBackup.backupIfVersionChanged(storeURL: storeURL, currentVersion: "1.1", defaults: defaults)
    }
    #expect(defaults.string(forKey: StoreBackup.versionKey) == "1.0")
}

@Test func legacyAppVersionKeyTriggersOneBackupThenMigratesKey() throws {
    let fm = FileManager.default
    let dir = try makeStoreDir()
    defer { try? fm.removeItem(at: dir) }

    let storeURL = dir.appending(path: "default.store")
    try Data("old".utf8).write(to: storeURL)
    let defaults = UserDefaults(suiteName: "StoreBackupTests-\(UUID().uuidString)")!
    defaults.set("1.0", forKey: StoreBackup.legacyVersionKey)

    // First launch of the versioned-schema build over an existing store: one backup.
    try StoreBackup.backupIfVersionChanged(storeURL: storeURL, currentVersion: "1.0.0", defaults: defaults)
    #expect(fm.fileExists(atPath: dir.appending(path: "Backups/pre-schema-1.0.0/default.store").path))
    #expect(defaults.string(forKey: StoreBackup.legacyVersionKey) == nil)
    #expect(defaults.string(forKey: StoreBackup.versionKey) == "1.0.0")

    // Second launch on the same schema: no new backup directory.
    try fm.removeItem(at: dir.appending(path: "Backups"))
    try StoreBackup.backupIfVersionChanged(storeURL: storeURL, currentVersion: "1.0.0", defaults: defaults)
    #expect(!fm.fileExists(atPath: dir.appending(path: "Backups").path))
}

@Test func failedLegacyBackupKeepsLegacyKeyForRetry() throws {
    let fm = FileManager.default
    let dir = try makeStoreDir()
    defer { try? fm.removeItem(at: dir) }

    let storeURL = dir.appending(path: "default.store")
    try Data("old".utf8).write(to: storeURL)
    let defaults = UserDefaults(suiteName: "StoreBackupTests-\(UUID().uuidString)")!
    defaults.set("1.0", forKey: StoreBackup.legacyVersionKey)

    try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: storeURL.path)
    defer { try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: storeURL.path) }

    #expect(throws: (any Error).self) {
        try StoreBackup.backupIfVersionChanged(storeURL: storeURL, currentVersion: "1.0.0", defaults: defaults)
    }
    // Neither key moved, so the next launch retries the one-time backup.
    #expect(defaults.string(forKey: StoreBackup.legacyVersionKey) == "1.0")
    #expect(defaults.string(forKey: StoreBackup.versionKey) == nil)
}
