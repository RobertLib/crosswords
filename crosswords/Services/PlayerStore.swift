import Foundation
import Observation
import os

/// Owns the player's saved data and writes it to disk shortly after every change.
@Observable
final class PlayerStore {
    private(set) var data: PlayerData

    /// `nil` keeps the data in memory only, e.g. in tests.
    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    /// False when an existing save file could not be read, so it is not overwritten.
    @ObservationIgnored private var canSave: Bool

    init(fileURL: URL? = PlayerStore.defaultURL) {
        self.fileURL = fileURL
        let loaded = fileURL.map { Self.load(from: $0) } ?? (data: PlayerData(), canSave: true)
        data = loaded.data
        canSave = loaded.canSave
    }

    static var defaultURL: URL {
        let directory = URL.applicationSupportDirectory
        return directory.appending(path: "player.json")
    }

    /// Reads the save file again if it couldn't be read at launch. The system can launch the
    /// app ahead of time ("prewarming"), even before the device is first unlocked after a
    /// restart, while the file is still encrypted. Returns whether the saved data was loaded.
    func reloadIfUnreadable() -> Bool {
        guard !canSave, let fileURL else { return false }
        let loaded = Self.load(from: fileURL)
        guard loaded.canSave else { return false }
        pendingSave?.cancel()
        pendingSave = nil
        data = loaded.data
        canSave = true
        return true
    }

    func update(_ change: (inout PlayerData) -> Void) {
        change(&data)
        scheduleSave()
    }

    /// Replaces all progress with a fresh start (used by "Reset progress").
    func reset(keepingSettings: Bool = true) {
        var fresh = PlayerData()
        if keepingSettings { fresh.settings = data.settings }
        data = fresh
        saveNow()
    }

    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        write(data)
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            self.write(self.data)
        }
    }

    private func write(_ snapshot: PlayerData) {
        guard canSave, let url = fileURL else { return }
        do {
            let encoded = try JSONEncoder().encode(snapshot)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoded.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            Logger.storage.error("Saving player data failed: \(error.localizedDescription)")
        }
    }

    private static func load(from url: URL) -> (data: PlayerData, canSave: Bool) {
        let contents: Data
        do {
            contents = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return (PlayerData(), true)
        } catch {
            // The file exists but can't be read right now; starting fresh would overwrite it.
            Logger.storage.error("Player data could not be read, not saving this session: \(error.localizedDescription)")
            return (PlayerData(), false)
        }
        do {
            return (try JSONDecoder().decode(PlayerData.self, from: contents), true)
        } catch {
            // Keep the undecodable file aside rather than silently overwriting it.
            Logger.storage.error("Player data unreadable, starting fresh: \(error.localizedDescription)")
            let backup = url.deletingPathExtension().appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: backup)
            return (PlayerData(), true)
        }
    }
}
