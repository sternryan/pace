# pace — macOS menu bar app showing Claude usage against its reset window

See `README.md` for what it shows, the two data-source modes, and the security posture.

## Commands

```bash
make test     # swift test — PaceCore's pure-logic unit tests
make build    # swift build -c release
make run      # swift run Pace, for local iteration
make app      # build + wrap into .build/Pace.app without installing
make install  # build, wrap into ~/Applications/Pace.app, sign
```

## Conventions

- **`PaceCore` stays free of AppKit and WebKit.** Parsing, pace math, and icon geometry are
  pure Swift and fully unit-tested; anything needing a framework belongs in the `Pace` target.
  That split is what makes the logic testable — don't erode it for convenience.
- The icon is monochrome except an ahead-of-pace lane, which turns red. Red is the only color
  the icon may ever show.

## Gotchas

- **⭐ Read this before touching `KeychainCredentialStore`.** Discovery is native
  (`SecItemCopyMatching`, attributes only), but the **decrypt deliberately shells out to
  `/usr/bin/security find-generic-password`**, with the native read only as fallback. Claude
  Code writes its item with `security add-generic-password -U`, so `/usr/bin/security` is
  permanently on that item's ACL and reading through it never prompts. A Pace-scoped grant is
  the opposite: every `claude` launch rewrites the item and wipes the grant, so the "Always
  Allow" the user clicked is gone by the next poll. **Do not "harden" this back to a
  SecItem-only read** — that is the bug, not the fix.
- **A recurring Keychain prompt has had three different root causes.** Before assuming the
  last fix regressed, correlate the newest item's `mdat` against actual `claude` process start
  times. Duplicate stale items were the first cause and are not automatically the next one.
- **The store keeps a 20-minute per-(service, account) cooldown** after a prompt-requiring
  failure and falls through to the next already-granted item. Removing it turns one denied
  decrypt into a prompt every refresh tick.
- **Multiple Keychain items share the service name** (plus suffixed variants some installs
  create). Enumerate all of them and let `ClaudeCodeCredential.selectFreshest` choose — a
  single-match read was observed returning a stale token right after a successful login.
- **The usage endpoint is undocumented and has already changed shape once.** Both known
  generations are handled. The contract is that Pace shows dimmed, clearly-labelled cached
  values rather than a wrong number — never let a parse failure surface as a plausible figure.
- `make install` signs with a stable local self-signed cert created on demand, so the Keychain
  grant survives rebuilds; ad-hoc signing is the fallback. Not notarized, not App Store.

## Where things live

- `Sources/PaceCore/` — the four providers (Claude, Codex, smithy, spend), the pacing engine,
  parsing, icon geometry, notification governor, cache, `ReportStore`, the loopback server, and
  the vendored `openusage` JSONL scanners under `Vendor/` (see `Vendor/VENDORED.md`).
- `Sources/Pace/` — the SwiftUI `MenuBarExtra` shell: icon rendering, dropdown UI, keychain store,
  preferences.
- `Sources/PaceCLI/` — the standalone `pace` CLI binary (`make cli` / `make install-cli`).
- `Scripts/build-app.sh`, `Scripts/ensure-signing-cert.sh` — what `make app` / `make install` run.
- `Scripts/pace-statusline-segment.sh` — installed by `make install-statusline` to
  `~/.claude/hooks/`, read by `~/.claude/bin/statusline.sh`.
