// gyro-helper: a launchd daemon that reads the IMU as root and streams it to the Gyro app.
//
// The app registers this daemon with SMAppService. launchd starts it on demand
// when the app connects to its Mach service.

import Foundation
import GyroXPC
import Security
import XPC
import os

private let log = Logger(subsystem: HelperService.machServiceName, category: "helper")

/// The signing information of the code at `url`, or of this helper when `url` is `nil`.
private func signingInformation(at url: URL? = nil) -> [String: Any]? {
    var staticCode: SecStaticCode?
    if let url {
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess else { return nil }
    } else {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
            SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess
        else { return nil }
    }
    var info: CFDictionary?
    guard let staticCode,
        SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
            == errSecSuccess
    else { return nil }
    return info as? [String: Any]
}

/// The app this helper was shipped in: launchd runs it from `Gyro.app/Contents/MacOS`.
nonisolated private var enclosingApp: URL {
    Bundle.main.executableURL!.resolvingSymlinksInPath()
        .deletingLastPathComponent()  // MacOS
        .deletingLastPathComponent()  // Contents
        .deletingLastPathComponent()
}

/// Only the Gyro app may connect, since the IMU stream can reveal what someone types.
///
/// A team-signed helper requires the app to come from the same team. An ad hoc one has
/// no team to check, so it requires the exact app it was shipped in, by its code
/// directory hash. Either way, if the signatures can't be read, nothing may connect.
private func clientRequirement() throws -> XPCPeerRequirement {
    guard let own = signingInformation() else { throw HelperFailure("Couldn't read the helper's own signature.") }
    if own[kSecCodeInfoTeamIdentifier as String] is String {
        return .isFromSameTeam(andMatchesSigningIdentifier: HelperService.appBundleIdentifier)
    }

    guard let app = signingInformation(at: enclosingApp),
        app[kSecCodeInfoIdentifier as String] as? String == HelperService.appBundleIdentifier,
        let cdhash = app[kSecCodeInfoUnique as String] as? Data
    else { throw HelperFailure("Couldn't read the signature of the app at \(enclosingApp.path).") }

    var facts = XPCDictionary()
    facts["signing-identifier"] = HelperService.appBundleIdentifier
    facts["cdhash"] = cdhash.withUnsafeBytes { xpc_data_create($0.baseAddress, $0.count) }
    return XPCPeerRequirement(lightweightCodeRequirements: facts)
}

private struct HelperFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

do {
    try MotionServer.run(requirement: clientRequirement())
} catch {
    log.fault("Couldn't start listener: \(String(describing: error), privacy: .public)")
    exit(1)
}
