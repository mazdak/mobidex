# Mobidex asc Distribution

Mobidex uses `asc` for App Store Connect and local Xcode distribution workflows.

Current app settings:

- Bundle ID: `com.getresq.mobidex`
- App Store Connect Bundle ID resource: `BCWXF9SR6H`
- App Store Connect app ID: `6767185049`
- TestFlight internal group: `Internal Testers` (`49de058d-8e57-4f7c-9929-3f600f867849`)
- TestFlight external group: `External Testers` (`28e9cfaa-239b-4afe-911d-8dc1671e941b`)
- Public TestFlight link: `https://testflight.apple.com/join/zmqueV6P`
- Current App Store version: `1.0` (`b6795222-81a8-4a12-b4d2-c01b6ee017fa`)
- Team ID: `JX3932QCN8`
- Xcode project: `Mobidex.xcodeproj`
- Scheme: `Mobidex`
- Configuration: `Release`

## One-time Auth

`asc` is currently configured with the default keychain credential `mobidex` using key ID `8MRPB3BGL6`. To recreate that setup on another machine:

```bash
asc auth login --name mobidex --key-id KEY_ID --issuer-id ISSUER_ID --private-key .secrets/AuthKey_KEY_ID.p8 --network
asc auth status
asc apps list --bundle-id com.getresq.mobidex --output table
```

Keep `.p8` files and `.asc/config.json` out of git. This repo's `.gitignore` excludes `.secrets/` and repo-local asc secret/config paths.

## New App Record

Create or confirm the Bundle ID first:

```bash
asc bundle-ids list --output table
asc bundle-ids create --identifier com.getresq.mobidex --name Mobidex --platform IOS
```

The exact Bundle ID currently exists as App Store Connect resource `BCWXF9SR6H`.

Apple does not expose official public API-key app creation through `asc apps create`. The CLI offers an experimental web-session path if the app record does not exist:

```bash
asc web apps create --name "Mobidex" --bundle-id "com.getresq.mobidex" --sku "MOBIDEX-IOS" --platform IOS --primary-locale en-US --version 1.0 --apple-id you@example.com
```

The app record currently exists as `6767185049` with App Store Connect name `Mobidex - mobidex`. Apple reported `Mobidex` as already in use during creation.

After creation, capture the App Store Connect app ID:

```bash
asc apps list --bundle-id com.getresq.mobidex --output table
```

## Ad Hoc

Register devices and ensure an Ad Hoc profile exists:

```bash
asc devices list --output table
asc devices register --name "Device Name" --udid DEVICE_UDID --platform IOS
asc signing fetch --bundle-id com.getresq.mobidex --profile-type IOS_APP_ADHOC --certificate-type IOS_DISTRIBUTION --device DEVICE_ID --create-missing --output .asc/signing
```

Build an Ad Hoc IPA:

```bash
asc workflow validate
asc workflow run --dry-run adhoc VERSION:1.0 BUILD_NUMBER:1
asc workflow run adhoc VERSION:1.0 BUILD_NUMBER:1
```

The IPA is written under `.asc/artifacts/`.

## TestFlight

Create or find the target TestFlight group:

```bash
asc testflight groups list --app 6767185049 --output table
```

Archive, export, upload, wait for processing, and add the build to a TestFlight group:

```bash
asc workflow run --dry-run testflight VERSION:1.0
asc workflow run testflight VERSION:1.0
```

The workflow sets `usesNonExemptEncryption=false` after upload before assigning the build to `Internal Testers`; App Store Connect will reject group assignment while export compliance is still unset.

For an external group that needs beta app review after upload, pass an explicit external group name or ID:

```bash
asc workflow run testflight_external BUILD_ID:BUILD_ID EXTERNAL_TESTFLIGHT_GROUP:"External Testers"
```

External TestFlight setup currently uses:

- Review contact is configured in App Store Connect; verify it before each external submission with `asc testflight review view --app 6767185049 --output table`.
- Demo account required: `false`
- Beta app description: Mobidex requires a tester-controlled SSH server running `codex-app-server`.
- Review note: do not provide a public demo SSH server; reviewers can inspect setup and connect to their own reachable host if available.
- Latest submitted external build: `1.0 (7)` / `d6f899b3-1f24-4bce-be78-295e41c23b79`, submitted on `2026-05-11`, approved for external beta testing.

Enable or refresh the public link:

```bash
asc testflight groups edit --id 28e9cfaa-239b-4afe-911d-8dc1671e941b --public-link-enabled --public-link-limit-enabled --public-link-limit 10000 --feedback-enabled
```

## Local Validation

This check does not require App Store Connect credentials:

```bash
Scripts/verify-ios-distribution-config.sh
```
