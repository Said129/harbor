import Foundation
import CommonCrypto
import Security

protocol ProfileCredentialChecking: Sendable {
    func verifies(_ password: String, credential: DeviceProfileCredential) async throws -> Bool
}
struct DeviceProfileCredentialChecker: ProfileCredentialChecking {
    func verifies(_ password: String, credential: DeviceProfileCredential) async throws -> Bool { try await credential.verifies(password) }
}
protocol ProfileCredentialDeriving: Sendable {
    func derive(_ password: String) async throws -> DeviceProfileCredential
}
struct DeviceProfileCredentialDeriver: ProfileCredentialDeriving {
    func derive(_ password: String) async throws -> DeviceProfileCredential { try await DeviceProfileCredential.create(password) }
}

/// Device-only PIN/password derivation. Never part of the Desktop roster document.
struct DeviceProfileCredential: Codable, Equatable, Sendable {
    let version: Int
    let salt: Data
    let rounds: UInt32
    let digest: Data
    var valid: Bool { version == 1 && salt.count == 32 && rounds >= 100_000 && rounds <= 2_000_000 && digest.count == 32 }

    static func create(_ password: String) async throws -> Self {
        guard validPassword(password) else { throw HarborError(code: "profile-password-format") }
        return try await Task.detached(priority: .userInitiated) {
            var salt = Data(count: 32)
            let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!) }
            guard status == errSecSuccess else { throw HarborError(code: "profile-password-random") }
            let rounds: UInt32 = 600_000
            return try Self(version: 1, salt: salt, rounds: rounds, digest: derive(password, salt: salt, rounds: rounds))
        }.value
    }
    func verifies(_ password: String) async throws -> Bool {
        guard valid, Self.validPassword(password) else { return false }
        return try await Task.detached(priority: .userInitiated) {
            let candidate = try Self.derive(password, salt: salt, rounds: rounds)
            var difference: UInt8 = 0
            for (left, right) in zip(candidate, digest) { difference |= left ^ right }
            return difference == 0
        }.value
    }
    static func validPIN(_ pin: String) -> Bool { pin.utf8.count == 4 && pin.utf8.allSatisfy { (48...57).contains($0) } }
    private static func validPassword(_ password: String) -> Bool { !password.isEmpty && password.utf8.count <= 1_024 }
    private static func derive(_ password: String, salt: Data, rounds: UInt32) throws -> Data {
        var output = Data(count: 32)
        let passwordBytes = Array(password.utf8)
        let status = passwordBytes.withUnsafeBytes { passwordBuffer in
            salt.withUnsafeBytes { saltBuffer in
                output.withUnsafeMutableBytes { result in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), passwordBuffer.bindMemory(to: Int8.self).baseAddress!, passwordBytes.count,
                                         saltBuffer.bindMemory(to: UInt8.self).baseAddress!, salt.count,
                                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds,
                                         result.bindMemory(to: UInt8.self).baseAddress!, result.count)
                }
            }
        }
        guard status == kCCSuccess else { throw HarborError(code: "profile-password-derive") }
        return output
    }
}
