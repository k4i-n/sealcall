# sealcall

Keep an API key in the macOS Keychain where only sealcall can read it, and define where it may be sent: one HTTPS host, and the methods and paths you allow. Programs call the API through sealcall and never get the key.

```
$ sealcall call cloudflare GET /client/v4/zones -o zones.json
HTTP 200
```

## How the key is protected

- Each key is in a Keychain item whose access list trusts only the signed sealcall binary. Any other reader, including `security find-generic-password`, gets a macOS dialog.
- The host and rules are stored in the same item as the key. Changing them needs Touch ID or your login password.
- sealcall makes the HTTP call itself. The key never goes to a file, an environment variable or a child process. Responses are scrubbed of it, and no command prints it.

## Install

macOS 14 or later and the Xcode command line tools.

```
git clone https://github.com/k4i-n/sealcall && cd sealcall
make signing-identity   # once: a "sealcall code signing" certificate in your login keychain
make install            # builds, signs, installs ~/.local/bin/sealcall
```

Every build is signed with that certificate, so the Keychain keeps trusting new builds. When macOS asks whether `codesign` may use the key, click **Allow**, never **Always Allow**.

## Use

```
sealcall add cloudflare --host api.cloudflare.com \
  --header 'Authorization: Bearer {key}' --allow 'GET /client/v4/**'
sealcall call cloudflare GET /client/v4/zones -o zones.json

sealcall add linear --host api.linear.app \
  --header 'Authorization: {key}' --allow 'POST /graphql'
sealcall call linear POST /graphql --data query.json -H 'Content-Type: application/json'

sealcall routes             # names, hosts and rules; never keys
sealcall rotate cloudflare  # new key, same rules
sealcall remove cloudflare
```

`add` reads the key from a hidden prompt, or from stdin with `--stdin`. `add`, `rotate` and `remove` ask for Touch ID.

`call` writes the body to stdout or `-o` and the status line to stderr, and exits 1 for status 400 and above. Redirects are returned, not followed.

### Rules

`--allow 'METHOD /path'` may be repeated. `*` matches within one path segment, `**` any number of segments. The query string is not matched. Paths with `..`, `//` or encoded `/` are refused.

Callers may send `Content-Type` and `Accept`, plus names added with `--caller-header`. `Authorization`, `Cookie` and `Host` are never accepted from the caller.

## Use cases

- **Scripts and scheduled jobs.** Call `sealcall call` instead of loading a `.env` file. No key sits on disk or in shell history.
- **Third-party code.** Dependencies, build scripts and editor extensions run as you and can read your files. They find no key to take.
- **AI coding agents.** Allow `sealcall call` and deny the rest. For Claude Code, in `~/.claude/settings.json`:

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
- **Sandboxes.** A sandbox limits the files and hosts a process reaches, but not a key handed to it. With sealcall the sandboxed command holds no key. If the sandbox blocks network or Keychain access, run sealcall outside it.

## An unexpected Keychain dialog means Deny

sealcall never shows a Keychain dialog; it fails with an error instead. A dialog naming a sealcall item or the signing key comes from another program.

## Limits

- An allowed route can do anything its rules allow. Use keys with the smallest scope the provider offers.
- Another process running as you can overwrite a route's item without reading it. The key is lost, not revealed; re-add the route.
- Scrubbing matches the exact key, not other encodings such as base64.
- Root, and a user who approves an unexpected dialog, are out of scope.

Details: [docs/threat-model.md](docs/threat-model.md).

## Develop

```
make test
make build
```

`SEALCALL_KEYCHAIN` points sealcall at another keychain file, for tests.

## License

Apache-2.0
