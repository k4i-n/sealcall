// Imports a PKCS#12 identity from stdin into the login keychain. The private key is
// non-extractable and trusts no application, so every signature needs a Keychain dialog.
import Foundation
import Security

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("import-identity: \(message)\n".utf8))
    exit(1)
}

guard let passphrase = ProcessInfo.processInfo.environment["SEALCALL_P12_PASS"] else {
    fail("SEALCALL_P12_PASS is not set")
}
let keychainPath = ProcessInfo.processInfo.environment["SEALCALL_KEYCHAIN"]
    ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Keychains/login.keychain-db").path
var keychain: SecKeychain?
guard SecKeychainOpen(keychainPath, &keychain) == errSecSuccess, let keychain else {
    fail("cannot open \(keychainPath)")
}
var access: SecAccess?
guard SecAccessCreate("sealcall code signing key" as CFString, [] as CFArray, &access) == errSecSuccess, let access else {
    fail("cannot create the access list")
}
var params = SecItemImportExportKeyParameters()
params.version = UInt32(SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION)
params.passphrase = Unmanaged.passRetained(passphrase as CFString as AnyObject)
params.accessRef = Unmanaged.passRetained(access)
params.keyAttributes = Unmanaged.passRetained([kSecAttrIsPermanent] as CFArray)
var format = SecExternalFormat.formatPKCS12
var type = SecExternalItemType.itemTypeAggregate
let data = FileHandle.standardInput.readDataToEndOfFile()
guard !data.isEmpty else { fail("no PKCS#12 data on stdin") }
let status = SecItemImport(data as CFData, nil, &format, &type, [], &params, keychain, nil)
guard status == errSecSuccess else {
    fail((SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus \(status)")
}
