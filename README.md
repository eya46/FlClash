<div>

[**简体中文**](README_zh_CN.md)

</div>

## FlClash

[![Downloads](https://img.shields.io/github/downloads/chen08209/FlClash/total?style=flat-square&logo=github)](https://github.com/chen08209/FlClash/releases/)[![Last Version](https://img.shields.io/github/release/chen08209/FlClash/all.svg?style=flat-square)](https://github.com/chen08209/FlClash/releases/)[![License](https://img.shields.io/github/license/chen08209/FlClash?style=flat-square)](LICENSE)

[![Channel](https://img.shields.io/badge/Telegram-Channel-blue?style=flat-square&logo=telegram)](https://t.me/FlClash)

A multi-platform proxy client based on ClashMeta, simple and easy to use, open-source and ad-free.

on Desktop:
<p style="text-align: center;">
    <img alt="desktop" src="snapshots/desktop.gif">
</p>

on Mobile:
<p style="text-align: center;">
    <img alt="mobile" src="snapshots/mobile.gif">
</p>

## Features

✈️ Multi-platform: Android, Windows, macOS and Linux

💻 Adaptive multiple screen sizes, Multiple color themes available

💡 Based on Material You Design, [Surfboard](https://github.com/getsurfboard/surfboard)-like UI

☁️ Supports data sync via WebDAV

✨ Support subscription link, Dark mode

## Use

### Linux

⚠️ Make sure to install the following dependencies before using them

   ```bash
    sudo apt-get install libayatana-appindicator3-dev
    sudo apt-get install libkeybinder-3.0-dev
   ```

### Android

Support the following actions

   ```bash
    com.follow.clash.action.START
    
    com.follow.clash.action.STOP
    
    com.follow.clash.action.TOGGLE
   ```

## Tailscale (tsnet) — known limitations

This fork integrates Tailscale via tsnet. A few rough edges are worth
knowing about before filing a report:

1. **Android VPN routes are set once at startup.** Android's
   `VpnService.Builder` cannot reconfigure routes after `establish()`.
   On VPN start FlClash polls tsnet for up to 6 seconds, reads the
   current peer-advertised subnets (e.g. `192.168.100.0/24`), and
   injects them into the VPN route table. If tsnet has not reached
   `Running` within that window, the subnets won't be injected — toggle
   the VPN off and on once the Tailscale page shows `Running` to pick
   them up.
2. **New peer subnets discovered after VPN start require a VPN
   restart.** If a peer comes online with a new subnet while the VPN
   is already running, that subnet won't be routed until the VPN is
   toggled off and on.
3. **Tile / broadcast-receiver cold starts rely on cached state.**
   When FlClash is launched without a Flutter engine (e.g. from the
   Quick Settings tile or a broadcast intent), VPN options are read
   from the last persisted sharedState on disk. The very first
   headless start may need a prior UI-based start so the Tailscale
   routes get cached.
4. **tsnet can get stuck in `Connecting` when the proxy is enabled
   right after app launch.** Occasionally, if Tailscale auto-connects
   on launch and the proxy is then turned on, tsnet is disconnected
   and stays in `Connecting`. Workaround: toggle the Tailscale
   **Enable** switch off and back on.

## Download

<a href="https://chen08209.github.io/FlClash-fdroid-repo/repo?fingerprint=789D6D32668712EF7672F9E58DEEB15FBD6DCEEC5AE7A4371EA72F2AAE8A12FD"><img alt="Get it on F-Droid" src="snapshots/get-it-on-fdroid.svg" width="200px"/></a> <a href="https://github.com/chen08209/FlClash/releases"><img alt="Get it on GitHub" src="snapshots/get-it-on-github.svg" width="200px"/></a>

## Build

1. Update submodules
   ```bash
   git submodule update --init --recursive
   ```

2. Install `Flutter` and `Golang` environment

3. Build Application

    - android

        1. Install  `Android SDK` ,  `Android NDK`

        2. Set `ANDROID_NDK` environment variables

        3. Run Build script

           ```bash
           dart .\setup.dart android
           ```

    - windows

        1. You need a windows client

        2. Install  `Gcc`，`Inno Setup`

        3. Run build script

           ```bash
           dart .\setup.dart windows --arch <arm64 | amd64>
           ```

    - linux

        1. You need a linux client

        2. Run build script

           ```bash
           dart .\setup.dart linux --arch <arm64 | amd64>
           ```

    - macOS

        1. You need a macOS client

        2. Run build script

           ```bash
           dart .\setup.dart macos --arch <arm64 | amd64>
           ```

## Star

The easiest way to support developers is to click on the star (⭐) at the top of the page.

<p style="text-align: center;">
    <a href="https://api.star-history.com/svg?repos=chen08209/FlClash&Date">
        <img alt="start" width=50% src="https://api.star-history.com/svg?repos=chen08209/FlClash&Date"/>
    </a>
</p>