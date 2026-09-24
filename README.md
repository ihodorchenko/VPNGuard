# VPNGuard

Native macOS Kill Switch that **blocks network access at the system level** to protected hosts when VPN is unavailable.

Protected by default:
- `claude.ai`
- `api.anthropic.com`

## How It Works

```
┌─────────────────┐     XPC      ┌──────────────────────┐
│  VPNGuard.app   │◄────────────►│  VPNGuardHelper      │
│  (Menu Bar UI)  │              │  (root via SMAppService)│
└────────┬────────┘              └──────────┬───────────┘
         │                                  │
    VPNMonitor                         pfctl / PF
    RouteChecker                       /var/run/vpnguard/pf.conf
    DNSResolver
```

1. **VPNMonitor** runs `route -n get` for each protected host every 2 seconds.
2. Traffic is allowed only when the route interface matches `utun*` (or a custom interface from Settings).
3. When VPN is lost, **ProtectionEngine** sends `ENABLE_BLOCK` to the privileged helper.
4. **VPNGuardHelper** writes PF rules and runs `pfctl` to block TCP/UDP to resolved IPs and kills existing connections via `pfctl -k`.
5. When VPN returns, blocking is automatically removed.

## Project Structure

```
VPNGuard/
├── App/                    # Application entry point
├── MenuBar/                # Status bar icon and menu
├── VPN/                    # VPNMonitor, RouteChecker, VPNState
├── Protection/             # ProtectionEngine, Rules, ConnectionRegistry
├── Firewall/               # PFManager, DNSResolver
├── Settings/               # SwiftUI settings panel
├── Logging/                # File logger
├── Resources/              # Info.plist, Launchd plist, assets
Shared/                     # Constants, IPCProtocol, PFRuleBuilder
VPNGuardHelper/             # Privileged helper tool (root)
```

## Requirements

- macOS 14.0+
- Xcode 15+
- Code signing (Team ID configured in the project) — required for SMAppService
- VPN client using `utun` interface (WireGuard, Tunnelblick, ProtonVPN, Mullvad)

## Build & Run

1. Open `VPNGuard.xcodeproj` in Xcode.
2. Select your Development Team in both targets (**VPNGuard** and **VPNGuardHelper**).
3. Build and run (**⌘R**).
4. On first launch the app registers the privileged daemon via **SMAppService**
   (macOS 13+). macOS may ask for approval; if so, allow VPNGuard in
   **System Settings → General → Login Items** and relaunch.

> Registration requires a code-signed build. An unsigned build from DerivedData,
> or one signed with a different Team ID than the one that registered the daemon,
> will fail to register.

## Menu Bar

| Icon | State |
|------|-------|
| 🟢 VG | VPN connected, protection active |
| 🔴 VG | VPN disconnected, **blocking active** |
| 🟡 VG | Checking routes |

Menu actions:
- **Enable / Disable Protection** — toggle kill switch
- **Refresh IPs** — re-resolve protected host DNS
- **Settings…** — configure VPN interface and hosts
- **Open Logs** — open `~/Library/Logs/VPNGuard/`

## Settings

| Setting | Default | Description |
|---------|---------|-------------|
| VPN interface prefix | `utun` | Route interface prefix for VPN detection |
| Custom interface | — | Exact interface name (e.g. `utun3`) |
| Protected hosts | claude.ai, api.anthropic.com | One host per line |
| Auto start | true | Enable protection on launch |

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

The pure logic in `Shared/` (PF rule building, VPN interface matching, XPC
command contract) is covered by a standalone SwiftPM test target:

```bash
swift test
```

These tests compile only the dependency-free `Shared/` sources and run without
launching the app, so no admin prompt or helper installation is triggered.

### Manual checks

### 1. VPN connected → hosts reachable

Connect VPN, launch VPNGuard. Menu shows **🟢 VG**. Verify:

```bash
curl -I https://claude.ai
```

### 2. VPN disconnected → hosts blocked

Disconnect VPN. Menu shows **🔴 VG**. Verify:

```bash
curl -I https://claude.ai   # should timeout / fail
```

### 3. Active session torn down

With VPN connected, open `https://claude.ai` in a browser. Disconnect VPN. The connection should drop within a few seconds (PF state kill).

### 4. VPN restored → access returns

Reconnect VPN. Menu shows **🟢 VG**. Refresh the browser — site loads again.

### Verify PF rules (requires root)

Anchor is registered when VPNGuard launches and installs the helper. If you see `Invalid argument`, the anchor is not yet installed:

```bash
# 1. Check if anchor exists
sudo pfctl -s Anchors | grep vpnguard

# 2. If empty — launch VPNGuard.app first (approve the daemon on first run)
#    Then re-check:
sudo pfctl -a com.apple/vpnguard -s rules

# 3. Check helper is running
sudo launchctl list | grep VPNGuard
```

Expected output when blocking is active:

```
block drop quick proto tcp to 104.x.x.x
```

## Security

- No `sudo` in the main app — all privileged operations go through **VPNGuardHelper**.
- Helper registered and managed by **SMAppService** (macOS 13+); the system
  validates the app and daemon code signatures.
- Communication over **XPC** with Mach service `by.home.VPNGuard.helper`.
- User password is never stored.

## PF Configuration

Rules file: `/var/run/vpnguard/pf.conf`

Example rule:

```
block drop quick proto tcp to 104.x.x.x
```

Anchor: `com.apple/vpnguard` (uses the system `com.apple/*` namespace — no /etc/pf.conf edits needed).

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Helper registration fails | Sign both targets with the same Team ID; approve VPNGuard in System Settings → General → Login Items |
| Blocking not working | Check logs, verify helper is running: `sudo launchctl list \| grep VPNGuard` |
| `pfctl: DIOCGETRULES: Invalid argument` | Anchor not installed yet — launch VPNGuard.app first (approve the daemon), then retry |
| False VPN detection | Set custom interface in Settings |
| IPs outdated | Use **Refresh IPs** from menu |

## License

Private project — all rights reserved.
