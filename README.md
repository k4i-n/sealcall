# sealcall

Let scripts and AI coding agents call an API with your key without being able to read the key.

```
$ sealcall call cloudflare GET /client/v4/zones -o zones.json
HTTP 200
```

The key lives in your macOS login Keychain, in an item that trusts only the signed sealcall binary. The caller names a route. sealcall adds the key to the request, sends it to the one host the route is bound to, and returns the response with the key scrubbed. There is no command that prints a key.

## Why

An agent or editor extension runs as your user. It can read a `.env` file, an environment variable, shell history, and also the Keychain: an item created with `security add-generic-password` trusts the `security` tool, so `security find-generic-password -w` returns it without a prompt. Tools that inject keys into a child process's environment (`op run`, envchain) hand the key to whatever command the agent runs.

sealcall makes the HTTP call itself, in process, and never gives the key to anything else.

## Install

macOS 14 or later and the Xcode command line tools. No Apple Developer account.

```
git clone https://github.com/nhkhai-vn/sealcall && cd sealcall
make signing-identity   # once: creates the "sealcall code signing" certificate in your login keychain
make install            # builds, signs, installs ~/.local/bin/sealcall
```

`make install` signs with that certificate, so the Keychain keeps trusting every build you make. macOS asks once per install whether `codesign` may use the signing key: click **Allow**, never **Always Allow**. The key trusts no application, so a process that tries to sign its own build with it gets the same dialog.

## Use

Add a route. The key is read from a hidden prompt, or from stdin with `--stdin` (for piping from a password manager). Touch ID or your login password confirms it.

```
sealcall add cloudflare --host api.cloudflare.com \
  --header 'Authorization: Bearer {key}' --allow 'GET /client/v4/**'

sealcall add linear --host api.linear.app \
  --header 'Authorization: {key}' --allow 'POST /graphql'
```

Call it:

```
sealcall call cloudflare GET /client/v4/zones -o zones.json
sealcall call linear POST /graphql --data query.json -H 'Content-Type: application/json'
echo '{"query":"{ viewer { id } }"}' | sealcall call linear POST /graphql --data - -H 'Content-Type: application/json'
```

The body goes to stdout or `-o`, the status line to stderr. The exit code is 1 for status 400 and above. Redirects are returned, not followed.

Manage routes:

```
sealcall routes             # names, hosts and rules; never keys
sealcall rotate cloudflare  # new key, same binding; Touch ID
sealcall remove cloudflare  # Touch ID
```

### Rules

`--allow 'METHOD /path'` may be repeated. In the path, `*` matches within one segment and `**` matches any number of whole segments. The query string is not matched.

| Rule | Allows | Refuses |
|---|---|---|
| `GET /client/v4/**` | `/client/v4`, `/client/v4/zones/1/dns_records` | `/client/v4x`, `POST /client/v4/zones` |
| `GET /repos/*/issues` | `/repos/sealcall/issues` | `/repos/a/b/issues` |
| `POST /graphql` | `/graphql?op=Viewer` | `/graphql/x` |

Paths with `..`, `.`, `//`, encoded `/` `\` `.`, or characters that should be percent-encoded are refused before any rule is checked.

Callers may send `Content-Type` and `Accept`. Add other header names per route with `--caller-header 'Anthropic-Version'`. `Authorization`, `Cookie`, `Host` and framing headers are never accepted from the caller.

### With an AI agent

Allow `sealcall call` and deny the commands that read the Keychain or replace the binary. For Claude Code, in `~/.claude/settings.json`:

```json
{
  "permissions": {
    "allow": ["Bash(sealcall call:*)"],
    "deny": [
      "Bash(sealcall add:*)", "Bash(sealcall rotate:*)", "Bash(sealcall remove:*)",
      "Bash(security find-generic-password:*)", "Bash(security dump-keychain:*)",
      "Edit(~/.local/bin/sealcall)", "Write(~/.local/bin/sealcall)"
    ]
  }
}
```

These rules reduce noise. The Keychain access list is what protects the key.

## An unexpected Keychain dialog means Deny

sealcall itself never shows a Keychain dialog: it reads with user interaction turned off and fails with an error instead. A dialog that names a sealcall item or the signing key comes from some other program. Click **Deny**.

## Limits

- An allowed route can be used for anything its rules allow. Create keys with the smallest scope the provider offers.
- Another process running as you can overwrite a route's Keychain item. It cannot read the old key, so this destroys the key without revealing it. If a route stops working, re-add it.
- Scrubbing matches the exact key. An API that echoes the key in another encoding, such as base64, is not covered.
- Root, and a user who approves a dialog they did not expect, are out of scope.

Details: [docs/threat-model.md](docs/threat-model.md).

## Develop

```
make test   # unit tests (Swift Testing)
make build
```

`SEALCALL_KEYCHAIN` points sealcall at another keychain file, for tests.

## License

Apache-2.0
