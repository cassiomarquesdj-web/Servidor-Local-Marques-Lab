# Build plan — iPhone Gambling Blocker

## Targets

- `GamblingBlocker`: SwiftUI application
- `GamblingBlockerShieldConfiguration`: Screen Time shield configuration extension
- `GamblingBlockerShieldAction`: Screen Time shield action extension
- `GamblingBlockerDeviceActivityMonitor`: Device Activity monitor extension
- `GamblingBlockerFilterDataProvider`: Network Extension content filter data provider
- `GamblingBlockerFilterControlProvider`: Network Extension content filter control provider

## Required Apple capabilities to evaluate

- Family Controls
- App Groups
- Network Extensions / Content Filter where eligible
- Device Activity
- Managed Settings

## Security posture

- Default deny for matched gambling categories.
- No remote collection of browsing content from the filter provider.
- Filtering rules are stored locally/shared only as required by the extension architecture.
- No bypass button in strict mode.

## Test matrix

- Safari
- WKWebView-based apps
- popular social apps containing betting links
- sportsbook domains
- casino domains
- affiliate/redirect domains
- deep links into gambling apps
- Wi-Fi and cellular
- Private Relay scenarios
- app installation/reinstallation
- reboot and filter reactivation
