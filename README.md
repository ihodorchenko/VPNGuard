# VPNGuard

Native macOS Kill Switch that **blocks network access at the system level** to protected hosts when VPN is unavailable.

Protected by default:
- `claude.ai`
- `api.anthropic.com`
- `chatgpt.com`
- `api.openai.com`
- `auth.openai.com`

## How It Works

```
┌─────────────────┐     XPC      ┌──────────────────────┐
│  VPNGuard.app   │◄────────────►│  VPNGuardHelper      │
│  (Menu Bar UI)  │              │  (root via SMJobBless)│
└────────┬────────┘              └──────────┬───────────┘
         │                                  │
    VPNMonitor                         pfctl / PF
    RouteChecker                       /var/run/vpnguard/pf.conf
    DNSResolver
```

1. **VPNMonitor** runs `route -n get` for each protected host in parallel every 2 seconds.
2. While protection is enabled, traffic to protected hosts is considered allowed only when their route interface matches `utun*` (or a custom interface from Settings).
3. When VPN is lost, **ProtectionEngine** sends `ENABLE_BLOCK` to the privileged helper.
4. **VPNGuardHelper** writes PF rules and runs `pfctl` to block TCP (all ports) and UDP/443 to resolved IPs, and kills existing connections via `pfctl -k`.
5. When VPN returns, blocking is automatically removed.

## Project Structure

```
VPNGuard/                    # Repository root
├── VPNGuard.xcodeproj       # Xcode project
├── VPNGuard/                # App target (menu bar UI)
│   ├── App/                 # @main AppDelegate and lifecycle wiring
│   ├── MenuBar/             # Status bar item and menu
│   ├── VPN/                 # VPNMonitor, RouteChecker
│   ├── Protection/          # ProtectionEngine, Rules, ConnectionRegistry
│   ├── Firewall/            # PFManager, DNSResolver
│   ├── Settings/            # SwiftUI Settings, Help, diagnostics
│   ├── Logging/             # File logger
│   ├── Resources/           # Asset catalog (app icon, accent color)
│   ├── Info.plist
│   └── VPNGuard.entitlements
├── VPNGuardHelper/          # Privileged helper target (runs as root)
├── Shared/                  # Pure shared logic: constants, IPC, PF rules/parsers, policies
├── Tests/                   # Standalone SwiftPM unit tests
├── docs/                    # Design notes (e.g. OPTION_B_SETTINGS.md)
├── scripts/                 # Maintenance scripts
├── LICENSE                  # MIT License
├── README.md
└── Package.swift            # SwiftPM test harness
```

## Requirements

- macOS 14.0+
- Xcode 26+ (requires the macOS 26 SDK or newer)
- Apple Developer signing (Team ID configured in project)
- VPN client using `utun` or a custom interface configured in Settings (WireGuard, Tunnelblick, ProtonVPN, Mullvad)

## Build & Run

1. Open `VPNGuard.xcodeproj` in Xcode.
2. Select the same Development Team for both targets (**VPNGuard** and **VPNGuardHelper**).
3. The Info.plist files reference Team ID `529YMJVWB5`. If your Team ID differs, update `SMPrivilegedExecutables` (`VPNGuard/Info.plist`) and `SMAuthorizedClients` (`VPNGuardHelper/Info.plist`) to match it.
4. Build and run (**⌘R**).
5. On first launch, macOS prompts for admin password to install the privileged helper via **SMJobBless**.

## Menu Bar

| Icon | State |
|------|-------|
| 🟢 VG | VPN connected, protection active |
| 🔴 VG | VPN disconnected, **blocking active** |
| 🟡 VG | Checking routes |
| 🟠 VG | Protection disabled |

Menu actions:
- **Enable / Disable Protection** — toggle kill switch
- **Refresh IPs** — re-resolve protected host DNS
- **Settings…** — configure VPN interface and hosts
- **Help…** — diagnostics and manual recovery commands
- **Open Logs** — open `~/Library/Logs/VPNGuard/`
- **Quit** — stop monitoring and exit

## Settings

| Setting | Default | Description |
|---------|---------|-------------|
| VPN interface prefix | `utun` | Route interface prefix for VPN detection |
| Custom interface | — | Exact interface name (e.g. `utun3`) |
| Protected hosts | claude.ai, api.anthropic.com, chatgpt.com, api.openai.com, auth.openai.com | One host per line; schemes, paths and ports are ignored; up to 32 hosts |
| Auto start | true | Enable protection on launch |

Hosts can be changed at any time without rebuilding: **Settings… → Protected Hosts → Save Hosts**. Schemes (`https://`), paths, ports, comments and duplicates are normalized automatically, and the Help panel checks the same list.

VPNGuard blocks resolved IP addresses, not URL paths: configure hostnames, IPv4 or IPv6 addresses. CIDR ranges are intentionally rejected in this version.

On macOS 26+ the native SwiftUI `Settings` scene is used. On macOS 14–15 the same view is hosted in an AppKit window.

See [`docs/OPTION_B_SETTINGS.md`](docs/OPTION_B_SETTINGS.md) for the design notes and future improvements.

## Logs

Logs are written to:

```
~/Library/Logs/VPNGuard/YYYY-MM-DD.log
```

Example:

```
2026-07-20 12:05:33

SECURITY

Blocked connection

Host:
api.anthropic.com

Reason:
VPN unavailable
```

## Testing

### Unit tests

The pure logic in `Shared/` (PF rule building and parsing, VPN interface
matching, host normalization, protection policies, XPC command contract) is
covered by a standalone SwiftPM test target with 56 tests:

```bash
swift test
```

These tests compile only the dependency-free `Shared/` sources and run without
launching the app, so no admin prompt or helper installation is triggered.

### Manual checks

#### 1. VPN connected → hosts reachable

Connect VPN, launch VPNGuard. Menu shows **🟢 VG**. Verify:

```bash
curl -I https://claude.ai
```

#### 2. VPN disconnected → hosts blocked

Disconnect VPN. Menu shows **🔴 VG**. Verify:

```bash
curl -I https://claude.ai   # should timeout / fail
```

#### 3. Active session torn down

With VPN connected, open `https://claude.ai` in a browser. Disconnect VPN. The connection should drop within a few seconds (PF state kill).

#### 4. VPN restored → access returns

Reconnect VPN. Menu shows **🟢 VG**. Refresh the browser — site loads again.

### Verify PF rules (requires root)

Anchor is registered when VPNGuard launches and installs the helper. If you see `Invalid argument`, the anchor is not yet installed:

```bash
# 1. Check if anchor exists
sudo pfctl -s Anchors | grep vpnguard

# 2. If empty — launch VPNGuard.app first (admin password required on first run)
#    Then re-check:
sudo pfctl -a com.apple/vpnguard -s rules

# 3. Check helper is running
sudo launchctl list | grep VPNGuard
```

Expected output when blocking is active:

```
block drop quick proto tcp to 104.x.x.x
block drop quick proto udp to 104.x.x.x port 443
```

## Security

- No `sudo` in the main app — all privileged operations go through **VPNGuardHelper**.
- Helper installed via **SMJobBless** with code signing verification (Apple deprecated SMJobBless in macOS 13; migration to `SMAppService` is a future task).
- Communication over **XPC** with Mach service `by.home.VPNGuard.helper`.
- User password is never stored.

## PF Configuration

Rules file: `/var/run/vpnguard/pf.conf`

Example rules:

```
block drop quick proto tcp to 104.x.x.x
block drop quick proto udp to 104.x.x.x port 443
```

Anchor: `com.apple/vpnguard` (uses the system `com.apple/*` namespace — no /etc/pf.conf edits needed).

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Helper install fails | Ensure both targets are signed with the Team ID referenced in the Info.plist files (`529YMJVWB5` by default) |
| Blocking not working | Check logs, verify helper is running: `sudo launchctl list \| grep VPNGuard` |
| `pfctl: DIOCGETRULES: Invalid argument` | Anchor not installed yet — launch VPNGuard.app first (admin prompt), then retry |
| False VPN detection | Set custom interface in Settings |
| IPs outdated | Use **Refresh IPs** from menu |

## License

Released under the [MIT License](LICENSE).
