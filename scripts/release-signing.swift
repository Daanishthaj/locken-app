#!/usr/bin/env swift
// Signs Locken releases so the in-app updater only installs DMGs you published.
//
//   swift scripts/release-signing.swift keygen
//       Creates the Ed25519 signing key once and stores it in your login Keychain
//       (service "app.locken.update-signing"). Prints the public key to paste into
//       AppUpdateManager.updatePublicKey. The private key never leaves the Keychain.
//
//   swift scripts/release-signing.swift sign web/public/Locken.dmg 1.0.3 3 "What's new"
//       Hashes the DMG, signs "locken-update|<version>|<build>|<sha256>" and writes
//       version, build, notes, sha256 and signature into web/public/version.json.
import CryptoKit
import Foundation
import Security

let service = "app.locken.update-signing"
let account = "ed25519"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func loadKey() -> Curve25519.Signing.PrivateKey? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecReturnData as String: true,
    ]
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
    return try? Curve25519.Signing.PrivateKey(rawRepresentation: data)
}

func storeKey(_ key: Curve25519.Signing.PrivateKey) {
    let attributes: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecAttrLabel as String: "Locken update signing key",
        kSecValueData as String: key.rawRepresentation,
        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    ]
    let status = SecItemAdd(attributes as CFDictionary, nil)
    guard status == errSecSuccess else { fail("Couldn't save the key to the Keychain (status \(status)).") }
}

let args = CommandLine.arguments.dropFirst()
switch args.first {
case "keygen":
    if let existing = loadKey() {
        print("A signing key already exists. Public key:")
        print(existing.publicKey.rawRepresentation.base64EncodedString())
        exit(0)
    }
    let key = Curve25519.Signing.PrivateKey()
    storeKey(key)
    print("Created a signing key in your login Keychain. Public key (paste into AppUpdateManager.updatePublicKey):")
    print(key.publicKey.rawRepresentation.base64EncodedString())

case "sign":
    let rest = Array(args.dropFirst())
    guard rest.count >= 3 else { fail("Usage: sign <dmg> <version> <build> [notes]") }
    let (dmgPath, version, buildText) = (rest[0], rest[1], rest[2])
    guard let build = Int(buildText) else { fail("Build must be a whole number.") }
    guard let key = loadKey() else { fail("No signing key in the Keychain. Run keygen first.") }
    guard let dmg = FileManager.default.contents(atPath: dmgPath) else { fail("Can't read \(dmgPath).") }
    let sha256 = SHA256.hash(data: dmg).map { String(format: "%02x", $0) }.joined()
    let message = Data("locken-update|\(version)|\(build)|\(sha256)".utf8)
    let signature = try key.signature(for: message).base64EncodedString()

    let versionPath = "web/public/version.json"
    var json = (FileManager.default.contents(atPath: versionPath))
        .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    json["version"] = version
    json["build"] = build
    json["sha256"] = sha256
    json["signature"] = signature
    if rest.count >= 4 { json["notes"] = rest[3] }
    let out = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
    try out.write(to: URL(fileURLWithPath: versionPath))
    print("Signed \(dmgPath) as \(version) (build \(build)).")
    print("sha256 \(sha256)")
    print("Updated \(versionPath). Publish the DMG and version.json together.")

default:
    fail("Usage: release-signing.swift keygen | sign <dmg> <version> <build> [notes]")
}
