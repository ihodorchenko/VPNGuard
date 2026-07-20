# VPNGuard

Native macOS Kill Switch that **blocks network access at the system level** to protected hosts when VPN is unavailable.

Protected by default:
- `claude.ai`
- `api.anthropic.com`

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
- Apple Developer signing (Team ID configured in project)
- VPN client using `utun` interface (WireGuard, Tunnelblick, ProtonVPN, Mullvad)

## Build & Run

1. Open `VPNGuard.xcodeproj` in Xcode.
2. Select your Development Team in both targets (**VPNGuard** and **VPNGuardHelper**).
3. Update `SMPrivilegedExecutables` / `SMAuthorizedClients` in Info.plist files if your Team ID differs from `529YMJVWB5`.
4. Build and run (**⌘R**).
5. On first launch, macOS prompts for admin password to install the privileged helper via **SMJobBless**.

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

# 2. If empty — launch VPNGuard.app first (admin password required on first run)
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
- Helper installed via **SMJobBless** with code signing verification.
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
| Helper install fails | Ensure both targets are signed with the same Team ID |
| Blocking not working | Check logs, verify helper is running: `sudo launchctl list \| grep VPNGuard` |
| `pfctl: DIOCGETRULES: Invalid argument` | Anchor not installed yet — launch VPNGuard.app first (admin prompt), then retry |
| False VPN detection | Set custom interface in Settings |
| IPs outdated | Use **Refresh IPs** from menu |

## License

Private project — all rights reserved.
