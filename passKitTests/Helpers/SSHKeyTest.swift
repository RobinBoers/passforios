//
//  SSHKeyTest.swift
//  passKitTests
//

import XCTest

@testable import passKit

final class SSHKeyTest: XCTestCase {
    // Throwaway keys generated for this test; the second one has the passphrase "secret".
    private let plainKey = """
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
    QyNTUxOQAAACBzCPhfIiVGGMXBc5JKeRZ+rzajJOioVDbeazALmeWWoAAAAJg2Bo7UNgaO
    1AAAAAtzc2gtZWQyNTUxOQAAACBzCPhfIiVGGMXBc5JKeRZ+rzajJOioVDbeazALmeWWoA
    AAAEAoRZsYSSBVMum/HdFsy4WrF13fe6RVnsLZiSKYhAGX6nMI+F8iJUYYxcFzkkp5Fn6v
    NqMk6KhUNt5rMAuZ5ZagAAAAEmF4Y2Vsb3R0QG1vby5sb2NhbAECAw==
    -----END OPENSSH PRIVATE KEY-----
    """

    private let protectedKey = """
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABBE7ekaV0
    CaT+aDvpJ3+yM5AAAAGAAAAAEAAAAzAAAAC3NzaC1lZDI1NTE5AAAAIPgr80yIQ14KJb69
    +QbJDv5AzUSGfBhn02IZVY0PgIdEAAAAoCn4r9MP3d+KRnG8Nj998I0RsPj7C8RiYtGFLR
    Pxl54QWL7hND3qodTVh43e44vz4QZKDRXB2jxJ0Z7sPcH3l5tSXOUsOEyPgoRVbTlWrctj
    I+4ozKKp1+NUXBFQMsoYcvtWMi3E87ILWXsVX5LCfZlCUC4Br2I4RUaAt1vKe2b3abo6B7
    onbM9cckjRYjMt7gguPK1sDxIPK5yzVCSCozM=
    -----END OPENSSH PRIVATE KEY-----
    """

    func testIsEncrypted() {
        XCTAssertFalse(SSHKey.isEncrypted(plainKey))
        XCTAssertTrue(SSHKey.isEncrypted(protectedKey))
        XCTAssertTrue(SSHKey.isEncrypted("-----BEGIN RSA PRIVATE KEY-----\nProc-Type: 4,ENCRYPTED\n-----END RSA PRIVATE KEY-----"))
        XCTAssertFalse(SSHKey.isEncrypted("not a key"))
    }

    func testFingerprint() {
        XCTAssertEqual(SSHKey.fingerprint(plainKey), "ED25519 SHA256:mQz5Tj3vfA4I1YN8Y4jTf9se8G0vTsoXOJdIaRapypw")
        XCTAssertEqual(SSHKey.fingerprint(protectedKey), "ED25519 SHA256:sy6jpin4EeiV6mTO6WbumUwxhEXdHyukz7cPKPNPIzg")
        XCTAssertNil(SSHKey.fingerprint("not a key"))
    }
}
