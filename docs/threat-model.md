# Threat model

The attacker is a process running as your user: an AI agent, an editor extension, a malicious dependency. It can read and write your files, run any command, and run sealcall. The asset is the key value.

## Defenses

| Attack | Defense |
|---|---|
| Read a key file or environment variable | None exists. Keys are only in Keychain items. |
| `security find-generic-password -w` | Each item's access list trusts only the sealcall binary's code requirement (identifier plus signing certificate). Any other reader gets a dialog. |
| Ask sealcall for the key | No such command. Response bodies and transport errors are scrubbed of the exact key string. |
| Send the key to another host | The host is stored in the same Keychain value as the key. A new value without the real key is useless. |
| Widen the allowed methods or paths | Rules are stored in that value too. |
| Replace or patch the sealcall binary | The modified binary no longer satisfies the code requirement. Reads fail; the attacker's own build would get a dialog. |
| Sign a modified build with your certificate | The private key is non-extractable and trusts no application. Every signature needs a dialog. |
| Attach a debugger, inject a library | The binary is signed with hardened runtime and without `get-task-allow`. |
| Read the key from a child process | sealcall makes the HTTP call in process with URLSession. It never starts a child process. |
| Follow a redirect to another host | Redirects are returned, not followed. |
| Send its own `Authorization`, `Cookie` or `Host` | Caller headers are limited to `Content-Type`, `Accept` and names declared on the route. |
| Path tricks (`..`, `%2f`, `//host`) | Refused before rule matching. |
| Plain HTTP | Routes are HTTPS only, TLS 1.2 or later. |

## Tested on macOS 26

These were checked with a scratch keychain and binaries signed with a self-signed certificate:

- A rebuild signed with the same certificate reads existing items without a dialog. An ad-hoc signed build loses access on every rebuild, which is why `make install` requires the certificate.
- A binary with a different signature gets `errSecAuthFailed` when it reads an item.
- A key imported by `security import` trusts `/usr/bin/security` for `export_clear` and `sign`. `make signing-identity` imports through `SecItemImport` with an empty trusted list instead, and `security export` then fails.
- `canEvaluatePolicy(.deviceOwnerAuthentication)` succeeds from a command line binary without an app bundle.

## Residual risks

- **Overwrite.** Any process running as you can replace the value of a generic password item without reading it, even when the item's `encrypt` entry trusts only sealcall. Deleting it is refused. An overwrite destroys the key and can bind the route to the attacker's own key and host. The real key is not revealed.
- **Dialog approval.** A user who clicks Allow or Always Allow on an unexpected dialog gives the key away.
- **Allowed routes.** Requests inside the rules can do anything the key allows.
- **Encodings.** Scrubbing matches the exact key string, not base64 or other encodings.
- **Deprecated API.** The access list uses `SecAccessCreate` and `SecTrustedApplicationCreateFromPath`, deprecated since macOS 10.10 but working. The replacement, the data protection keychain with an access group, needs an Apple Developer team entitlement.
