# Releasing JFC

`Scripts/release.sh` is the canonical direct-distribution path. It produces a
universal signed DMG, submits it to Apple, staples the accepted ticket, and
checks the final artifact with Gatekeeper.

## One-time setup on a release Mac

1. Install a **Developer ID Application** certificate and its private key in
   the login Keychain. A Developer ID Installer certificate is not needed for a
   DMG. Confirm the identity is available:

   ```sh
   security find-identity -v -p codesigning
   ```

2. Create the ignored local configuration:

   ```sh
   cp .env.example .env.local
   ```

   Fill in the full identity printed above, the developer team ID, and the
   Keychain profile name. These values identify the publisher but are not
   passwords. `Scripts/release.sh` loads the file itself using `/bin/sh`, so the
   command works unchanged from fish, zsh, or bash.

3. At <https://account.apple.com/>, create an app-specific password for
   notarization. Do not use the normal Apple Account password.

4. Store the notarization credentials in Keychain once:

   ```sh
   xcrun notarytool store-credentials "JFC-notary" \
     --apple-id "you@example.com" \
     --team-id "YOURTEAMID"
   ```

   Enter the app-specific password at the secure prompt. The password is stored
   by macOS Keychain under the profile name; it does not go in `.env.local` or
   the repository. If a different profile name is used, put that name in
   `JFC_NOTARY_PROFILE`.

5. Verify that `notarytool` can authenticate:

   ```sh
   xcrun notarytool history --keychain-profile "JFC-notary"
   ```

   `No submission history` is a successful authenticated response on a new
   account. A missing-profile or authentication error is not.

## Build and notarize

Release from a clean worktree:

```sh
Scripts/release.sh
```

The script performs these operations in order:

1. Finds the configured Developer ID Application identity.
2. Builds universal `arm64` and `x86_64` app and login-helper binaries.
3. Signs the helper and app inside-out with Hardened Runtime and secure
   timestamps, then verifies the signature and configured team ID.
4. Builds the styled DMG and signs it with the same identity.
5. Submits the DMG with `notarytool` and waits for an `Accepted` result. On
   rejection, it retrieves Apple's diagnostic log.
6. Staples and validates the ticket, runs Gatekeeper assessment, and prints the
   SHA-256 digest.

The output is `dist/JFC-<version>.dmg`. Do not modify or repackage it after this
point; any change requires rebuilding and notarizing again.

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
