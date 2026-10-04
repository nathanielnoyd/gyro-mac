// gyro-helper: a launchd daemon that reads the IMU as root and streams it to the Gyro app.
//
// The app registers this daemon with SMAppService. launchd starts it on demand
// when the app connects to its Mach service.

import GyroXPC
import os
import Security
import XPC

private let log = Logger(subsystem: HelperService.machServiceName, category: "helper")

/// The Team ID this helper is signed with, or `nil` for ad hoc builds.
private func signingTeamIdentifier() -> String? {
    var code: SecCode?
    var staticCode: SecStaticCode?
    var info: CFDictionary?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
          SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
          SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
    else { return nil }
    return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
}

/// Only the Gyro app may connect. Team-signed builds also require the app to come from the same team.
/// Ad hoc builds can only check the signing identifier, which any local code could claim.
private func clientRequirement() -> XPCPeerRequirement {
    if signingTeamIdentifier() != nil {
        return .isFromSameTeam(andMatchesSigningIdentifier: HelperService.appBundleIdentifier)
    }
    var facts = XPCDictionary()
    facts["signing-identifier"] = HelperService.appBundleIdentifier
    return XPCPeerRequirement(lightweightCodeRequirements: facts)
}

do {
    try MotionServer.run(requirement: clientRequirement())
} catch {
    log.fault("Couldn't start listener: \(error, privacy: .public)")
    exit(1)
}
