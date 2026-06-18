# Qobuz Discord Presence

A tiny macOS menu bar app that publishes the current Qobuz track to Discord Rich Presence.

## Build

```sh
chmod +x scripts/build-app.sh
scripts/build-app.sh
```

The app is created at:

```text
dist/Qobuz Discord Presence.app
```

## Setup

1. Launch `dist/Qobuz Discord Presence.app`.
2. Start playing music in Qobuz.

The app talks to your already logged-in local Discord desktop client. It auto-detects Discord, Discord Canary, or Discord PTB, and can open Discord if it is not running.

The app reads macOS Now Playing data. The Qobuz-only filter is available in the menu bar UI, but it is off by default because macOS source-app metadata is private and can vary between releases.

## Notes

- Discord must be installed on the same Mac. Your self account is used automatically because Discord Rich Presence runs through the local desktop client.
- The app uses Discord's local IPC socket; it does not need a bot token.
- The app uses Music Presence's public Qobuz Discord application ID, so you do not need to paste your own ID.
- Discord Rich Presence still requires an application ID internally; this app just bundles the Qobuz one.
- Album art is not sent by default because Discord Rich Presence image assets must be configured on the Discord application.

## Privacy

The app reads Qobuz playback metadata from local Qobuz files in `~/Library/Application Support/Qobuz`. It does not store Discord tokens, Qobuz credentials, or bot credentials.
