import AppKit
import SwiftUI

struct SettingsPopoverView: View {
    let directory: URL
    let screenAccess: Bool
    let hotkeyAvailable: Bool
    let capture: () -> Void
    let chooseFolder: () -> Void
    let openFolder: () -> Void
    let permissions: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(nsImage: SnapIcon.menuBarImage()).accessibilityHidden(true)
                Text("Snap").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("Settings").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Button(action: capture) {
                HStack {
                    Label("Capture", systemImage: "camera")
                    Spacer()
                    Text("⌘⇧S").font(.system(size: 11))
                }
                .frame(maxWidth: .infinity)
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.regular)
            if !hotkeyAvailable {
                Text("⌘⇧S is in use by another app.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Save folder").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(directory.lastPathComponent).font(.system(size: 12))
                        .lineLimit(1).truncationMode(.middle).help(directory.path)
                }
                Spacer(minLength: 8)
                Button("Choose…", action: chooseFolder).controlSize(.small)
            }
            HStack {
                Text("Screen access").font(.system(size: 12))
                Spacer()
                if screenAccess {
                    Label("Allowed", systemImage: "checkmark.circle")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    Button("Allow…", action: permissions).controlSize(.small)
                }
            }
            Divider()
            HStack {
                Button("Open folder", action: openFolder)
                Spacer()
                Button("Quit", action: quit).keyboardShortcut("q")
            }
            .buttonStyle(.borderless).controlSize(.small)
        }
        .padding(14).frame(width: 280)
    }
}

struct PermissionView: View {
    let request: () -> Void
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "viewfinder").font(.system(size: 36, weight: .light))
                .accessibilityHidden(true)
            Text("Allow Snap to capture your screen")
                .font(.title2.weight(.semibold))
            Text("Choose an area, a window or a full display. Snap copies the image to your clipboard. Press ↑ during capture to also save it to Desktop.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("In System Settings, turn on Snap under Screen & System Audio Recording. Snap captures still images only; it doesn’t record audio.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Open System Settings", action: request)
                    .buttonStyle(.borderedProminent).tint(.primary)
                    .keyboardShortcut(.defaultAction)
                Button("Try Again", action: retry).buttonStyle(.bordered)
            }
        }
        .padding(28).frame(width: 420).textSelection(.enabled)
    }
}

struct ReceiptView: View {
    let image: NSImage
    let directory: String?
    let copied: Bool
    let showFile: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 46).clipped().accessibilityLabel("Captured screenshot")
            VStack(alignment: .leading, spacing: 4) {
                Text(directory == nil ? "Copied" : (copied ? "Saved · Copied" : "Saved"))
                    .font(.system(size: 12, weight: .semibold))
                if let directory {
                    Text(directory).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if directory != nil {
                Button(action: showFile) { Image(systemName: "folder") }
                    .buttonStyle(.plain).help("Show in Finder").accessibilityLabel("Show screenshot in Finder")
            }
            Button(action: dismiss) { Image(systemName: "xmark") }
                .buttonStyle(.plain).help("Dismiss").accessibilityLabel("Dismiss screenshot")
        }
        .padding(14).frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
