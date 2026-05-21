# PortBridge

> One-click SSH port forwarding from your macOS menu bar.

[![Release](https://img.shields.io/github/v/release/yhzion/PortBridge)](https://github.com/yhzion/PortBridge/releases)
[![CI](https://github.com/yhzion/PortBridge/actions/workflows/release.yml/badge.svg)](https://github.com/yhzion/PortBridge/actions/workflows/release.yml)
[![License](https://img.shields.io/github/license/yhzion/PortBridge)](LICENSE)
![Platform](https://img.shields.io/badge/macOS-14%2B-blue)

<p align="center">
  <img src="docs/assets/main-window.png" alt="PortBridge main window" width="420">
</p>

PortBridge scans listening ports on hosts in your `~/.ssh/config` and forwards them to `localhost` with `ssh -L`. No more remembering long `-L` flags.

## Features

- 🔭 **Scan remote ports** automatically from `~/.ssh/config` hosts
- ⭐ **Pin favorites** for ports you use every day
- 🚀 **Launch at login** with favorite forwards started automatically
- 🍔 **Menu bar resident** — Dock icon optional, right-click toggles all favorites
- 🔁 **Resolve port conflicts** inline by picking a fallback local port
- 🌐 **Open in browser** with one click
- ✏️ **Edit servers safely** — auto-reconnects active forwards when identity changes, blocks duplicate `(user, host, port)` entries
- 🔔 **Update notifications** — checks GitHub Releases, shows a menu bar badge and first-detection banner (skip version or disable in menu)

<p align="center">
  <img src="docs/assets/menubar-popover.png" alt="PortBridge menu bar" width="360">
</p>

## Install

### One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/yhzion/PortBridge/main/install-release.sh | bash
```

Downloads the latest release zip, installs to `/Applications/PortBridge.app`, and clears the quarantine attribute.

### Manual

1. Download `PortBridge.zip` from [Releases](https://github.com/yhzion/PortBridge/releases)
2. Unzip and move `PortBridge.app` to `/Applications`
3. If macOS blocks launch:
   ```bash
   xattr -dr com.apple.quarantine /Applications/PortBridge.app
   ```

## Requirements

- macOS 14 (Sonoma) or later
- SSH key authentication configured in `~/.ssh/config`
- Remote hosts: Linux with `ss` or `lsof` available

## Troubleshooting

**"App can't be opened because the developer cannot be verified"**

PortBridge ships ad-hoc signed — no Developer ID or notarization. Bypass once:

```bash
xattr -dr com.apple.quarantine /Applications/PortBridge.app
```

Or in Finder, right-click `PortBridge.app` → **Open** → **Open**.

## Build from source

```bash
./install.sh
```

Requires Xcode. Builds Release, ad-hoc signs, and installs to `/Applications/PortBridge.app`.

## Privacy

PortBridge contacts `api.github.com` only to check for new releases. See [docs/PRIVACY.md](docs/PRIVACY.md) for what is and isn't sent.

## License

MIT — see [LICENSE](LICENSE). This repository does not accept external contributions.
