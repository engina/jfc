# Releasing JFC

`scripts/release.sh` is the canonical direct-distribution path. It produces a
universal signed DMG, submits it to Apple, staples the accepted ticket, and
qualifies that exact DMG through the complete disposable-VM lifecycle before
creating the release tag.

## One-time setup on a release Mac

1. Install `git-cliff` for Conventional Commits version calculation:

   ```sh
   brew install git-cliff
   ```

2. Install a **Developer ID Application** certificate and its private key in
   the login Keychain. A Developer ID Installer certificate is not needed for a
   DMG. Confirm the identity is available:

   ```sh
   security find-identity -v -p codesigning
   ```

3. Create the ignored local configuration:

   ```sh
   cp .env.example .env.local
   ```

   Fill in the full identity printed above, the developer team ID, and the
   Keychain profile name. These values identify the publisher but are not
   passwords. `scripts/release.sh` loads the file itself using `/bin/sh`, so the
   command works unchanged from fish, zsh, or bash.

4. At <https://account.apple.com/>, create an app-specific password for
   notarization. Do not use the normal Apple Account password.

5. Store the notarization credentials in Keychain once:

   ```sh
   xcrun notarytool store-credentials "JFC-notary" \
     --apple-id "you@example.com" \
     --team-id "YOURTEAMID"
   ```

   Enter the app-specific password at the secure prompt. The password is stored
   by macOS Keychain under the profile name; it does not go in `.env.local` or
   the repository. If a different profile name is used, put that name in
   `JFC_NOTARY_PROFILE`.

6. Verify that `notarytool` can authenticate:

   ```sh
   xcrun notarytool history --keychain-profile "JFC-notary"
   ```

   `No submission history` is a successful authenticated response on a new
   account. A missing-profile or authentication error is not.

## Build and notarize

Release from a clean worktree with one command:

```sh
scripts/release.sh
```

If `HEAD` has a `vMAJOR.MINOR.PATCH` tag, that tag is the release version.
Otherwise, `git-cliff` calculates the next version from Conventional Commits
since the latest version tag. `fix:` increments patch, `feat:` increments
minor, and a commit marked with `!` or `BREAKING CHANGE` increments major. The
bundle build number is the Git commit count.

An explicit version remains available for exceptional releases:

```sh
scripts/release.sh 0.2.0
```

To notarize the current dirty worktree strictly for local testing:

```sh
JFC_ALLOW_DIRTY=1 scripts/release.sh
```

Uncommitted changes are included in `dist/JFC-<version>-test.dmg` but cannot
influence the version calculated from Git history. Dirty test releases never
create a release manifest or Git tag and cannot overwrite the official DMG.
They run the same E2E qualification by default.

To deliberately bypass all automated tests:

```sh
scripts/release.sh --no-test
```

`--no-test` still builds, signs, notarizes, staples, and validates the DMG. It
records the official manifest's E2E status as `skipped`; it is the only release
mode that skips the test suite.

The default script performs these operations in order:

1. Resolves the release version and runs formatting and E2E unit checks.
2. Finds the configured Developer ID Application identity.
3. Builds universal `arm64` and `x86_64` binaries and injects the resolved
   version into every bundled app.
4. Signs the helpers and app inside-out with Hardened Runtime and secure
   timestamps, then verifies the signature and configured team ID.
5. Builds the styled DMG and signs it with the same identity.
6. Submits the DMG with `notarytool` and waits for an `Accepted` result. On
   rejection, it retrieves Apple's diagnostic log.
7. Staples and validates the ticket and runs Gatekeeper assessment.
8. Writes a pending `dist/JFC-<version>.release.json` containing the source
   commit, build, notarization submission, and SHA-256 digest.
9. Clones the pristine macOS VM baseline, transfers the exact notarized DMG,
   confirms its SHA-256 digest, ticket, Gatekeeper result, and code identity in
   the guest, installs it, and completes Accessibility onboarding.
10. Runs all 12 JFC-on scenarios and the Stop, Start, and agent-crash-recovery
    lifecycle checks.
11. Enables Start at Login, gracefully reboots, verifies hidden operation and
    click delivery, disables it, reboots again, and verifies both absence and
    the expected swallowed-click control.
12. Runs all seven JFC-off controls, verifies final status, uninstalls JFC,
    proves product cleanup, and deletes the disposable VM.
13. Marks E2E `passed` in the manifest and creates the annotated `v<version>`
    Git tag. Any failed gate leaves the release untagged.

The output is `dist/JFC-<version>.dmg`. Do not modify or repackage it after this
point; any change requires rebuilding and notarizing again.

The command is safe to rerun. A matching notarized DMG and manifest are reused
without another notarization submission. A `pending` or `failed` artifact is
sent through E2E again; a `passed` release is a no-op apart from recreating a
missing matching tag. A tag or artifact that conflicts with the current commit
is never overwritten. The script does not push the tag or publish a GitHub
release.

## Independent verification

Run these against the exact DMG to be distributed:

```sh
xcrun stapler validate -v dist/JFC-<version>.dmg
spctl --assess --type open --context context:primary-signature \
  --verbose=4 dist/JFC-<version>.dmg
hdiutil verify dist/JFC-<version>.dmg
shasum -a 256 dist/JFC-<version>.dmg
```

Gatekeeper must print `accepted` and `source=Notarized Developer ID`. A signed
but unnotarized image instead reports `Unnotarized Developer ID` and produces
the unpolished warning this release path is intended to prevent.

## What remains private

- `.env.local` is gitignored and contains local publisher identifiers only.
- Signing private keys remain in Keychain.
- The Apple app-specific password remains in the `notarytool` Keychain profile.
- CI must supply the same inputs through its secret store and a temporary
  Keychain; no certificate, private key, password, or publisher-specific value
  belongs in tracked files.

## Apple references

- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
- [Creating distribution-signed code for the Mac](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/)
- [Creating Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates)
