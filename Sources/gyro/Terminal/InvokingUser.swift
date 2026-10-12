import Foundation

/// The user who ran `sudo`, so files land in their home and belong to them, not root.
enum InvokingUser {
    private static let environment = ProcessInfo.processInfo.environment

    static var home: URL {
        if let name = environment["SUDO_USER"], let home = FileManager.default.homeDirectory(forUser: name) {
            return home
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// Creates `url` and any missing parents, owned by the user.
    static func createDirectory(_ url: URL) throws {
        var missing: [URL] = []
        var parent = url
        while !FileManager.default.fileExists(atPath: parent.path) {
            missing.append(parent)
            parent.deleteLastPathComponent()
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        missing.forEach(giveOwnership)
    }

    static func giveOwnership(of url: URL) {
        guard let uid = environment["SUDO_UID"].flatMap(uid_t.init),
            let gid = environment["SUDO_GID"].flatMap(gid_t.init)
        else { return }
        chown(url.path, uid, gid)
    }
}
