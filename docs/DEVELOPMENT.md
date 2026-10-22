# Development

Snap uses Swift 6 and targets macOS 14 or later. It has no package dependencies.

- AppKit owns the menu bar, settings popup, capture panels and pointer events.
- SwiftUI draws the settings, permission and result views.
- ScreenCaptureKit takes each display image before the capture controls appear.
- Each capture mode uses that stored image. Region crops the visible window area; it does not capture hidden content behind other windows. For a window that spans displays, it captures the part on the current display.
- The capture controller owns cancellation, mode changes and output. An actor encodes PNG images and writes files.
- The global shortcut uses Carbon. Snap does not need Accessibility access for it.
- The menu bar and app icon use the same original capture-frame artwork in `SnapIcon.swift`.

## Build

Run `./scripts/build.sh` to create `build/Snap.app`. The script uses a full Xcode installation at its standard path when available. It respects an explicit `DEVELOPER_DIR` value. It signs the app for local use; it does not notarize or publish it.

Run `./scripts/install.sh` to install the app in `/Applications`. Quit a running copy before you replace it. The script keeps the earlier app in `~/Library/Application Support/Snap/Backups`.

## Local signing and screen access

`scripts/sign.sh` creates a local code-signing identity once and reuses it. Its private key is non-extractable in the login Keychain, with access restricted to `/usr/bin/codesign`. Only its public certificate fingerprint is stored in `~/Library/Application Support/Snap/Signing/identity.sha1`. No system trust settings are changed and no credentials belong in this repository.

The designated requirement binds `dev.matthew.snap` to that certificate, so different builds retain the same app identity. A missing signing key fails the build instead of silently creating a replacement. To use an existing Apple-issued certificate, set `SNAP_SIGNING_IDENTITY` to its name or fingerprint and keep that choice consistent across updates. Ad hoc signing is rejected because its build-specific identity invalidates Screen Recording approval.

Switching from the old ad hoc build needs one permission migration: remove Snap from **System Settings → Privacy & Security → Screen & System Audio Recording**, add `/Applications/Snap.app` again, and choose **Quit & Reopen**. Later builds signed with the same identity retain that approval. macOS may still show its own periodic access reminders.

Run `./scripts/check-signing.sh` after building to verify that two different app payloads satisfy the same designated requirement, while an ad hoc signature and modified resources fail validation. Local signing does not provide notarization or a Developer ID distribution signature. See [Apple’s explanation of designated requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).

## Checks

The tests cover mode wrapping, Retina crop boundaries, display coordinates, reverse drags, small clicks, cursor updates, frozen-image data, PNG encoding and distinct output filenames. Native pointer tests call the AppKit event handlers with real `NSEvent` values, including stale arrow/text cursors and the cursor for each capture mode.

Live checks on macOS 27.2 used one 1512 × 982-point Retina display at 2×. Full-screen output measured 3024 × 1964 pixels. The saved PNG matched the clipboard bytes. Saving off created no file; saving on created one. Each new capture reset saving to off.

The UI automation tool cannot send a pointer drag to the borderless capture panel. Native event tests cover that path. Additional physical displays, older macOS versions and a full assistive-technology matrix have not been tested.
