<div>

[**English**](README.md)

</div>

## FlClash

[![Downloads](https://img.shields.io/github/downloads/chen08209/FlClash/total?style=flat-square&logo=github)](https://github.com/chen08209/FlClash/releases/)[![Last Version](https://img.shields.io/github/release/chen08209/FlClash/all.svg?style=flat-square)](https://github.com/chen08209/FlClash/releases/)[![License](https://img.shields.io/github/license/chen08209/FlClash?style=flat-square)](LICENSE)

[![Channel](https://img.shields.io/badge/Telegram-Channel-blue?style=flat-square&logo=telegram)](https://t.me/FlClash)

基于ClashMeta的多平台代理客户端，简单易用，开源无广告。

on Desktop:
<p style="text-align: center;">
    <img alt="desktop" src="snapshots/desktop.gif">
</p>

on Mobile:
<p style="text-align: center;">
    <img alt="mobile" src="snapshots/mobile.gif">
</p>

## Features

✈️ 多平台: Android, Windows, macOS and Linux

💻 自适应多个屏幕尺寸,多种颜色主题可供选择

💡 基本 Material You 设计, 类[Surfboard](https://github.com/getsurfboard/surfboard)用户界面

☁️ 支持通过WebDAV同步数据

✨ 支持一键导入订阅, 深色模式

## Use

### Linux

⚠️ 使用前请确保安装以下依赖

   ```bash
    sudo apt-get install libayatana-appindicator3-dev
    sudo apt-get install libkeybinder-3.0-dev
   ```

### Android

支持下列操作

   ```bash
    com.follow.clash.action.START
    
    com.follow.clash.action.STOP
    
    com.follow.clash.action.TOGGLE
   ```

## Tailscale (tsnet) — 已知限制

本分支通过 tsnet 集成 Tailscale，使用前请注意以下已知问题：

1. **Android VPN 路由只能在启动时设置一次。** Android 的
   `VpnService.Builder` 在 `establish()` 之后无法再动态修改路由。
   VPN 启动时 FlClash 会在最多 6 秒内 poll tsnet，读取当前 peer
   广告的子网（如 `192.168.100.0/24`）并注入到 VPN 路由表。若
   tsnet 在该窗口内未进入 `Running`，子网不会被注入——等
   Tailscale 页面显示 `Running` 后重新开关一次 VPN 即可生效。
2. **VPN 启动后新上线 peer 的子网需要重启 VPN 才能路由。**
   若 VPN 已运行时有 peer 上线并广告了新子网，该子网不会被
   路由，需要关闭 VPN 再重新开启。
3. **Tile / 广播拉起的冷启动依赖磁盘缓存。**
   当 FlClash 在没有 Flutter 引擎的情况下被拉起（例如快捷面板
   磁贴或广播 Intent），VpnOptions 会从磁盘上上次保存的
   sharedState 读取。第一次无头启动可能需要先经过一次 UI 启动
   以便把 Tailscale 路由缓存下来。
4. **应用启动后立即开启代理，tsnet 有时会卡在 `Connecting`。**
   偶发情况下，Tailscale 在应用启动时自动连接，紧接着开启
   代理会导致 tsnet 被断开并一直停留在 `Connecting`。临时方法：
   把 Tailscale 的 **Enable** 开关关闭后再打开即可。

## Download

<a href="https://chen08209.github.io/FlClash-fdroid-repo/repo?fingerprint=789D6D32668712EF7672F9E58DEEB15FBD6DCEEC5AE7A4371EA72F2AAE8A12FD"><img alt="Get it on F-Droid" src="snapshots/get-it-on-fdroid.svg" width="200px"/></a> <a href="https://github.com/chen08209/FlClash/releases"><img alt="Get it on GitHub" src="snapshots/get-it-on-github.svg" width="200px"/></a>

## Build

1. 更新 submodules
   ```bash
   git submodule update --init --recursive
   ```

2. 安装 `Flutter` 以及 `Golang` 环境

3. 构建应用

    - android

        1. 安装  `Android SDK` ,  `Android NDK`

        2. 设置 `ANDROID_NDK` 环境变量

        3. 运行构建脚本

           ```bash
           dart .\setup.dart android
           ```

    - windows

        1. 你需要一个windows客户端

        2. 安装 `Gcc`，`Inno Setup`

        3. 运行构建脚本

           ```bash
           dart .\setup.dart windows --arch <arm64 | amd64>
           ```

    - linux

        1. 你需要一个linux客户端

        2. 运行构建脚本

           ```bash
           dart .\setup.dart linux --arch <arm64 | amd64>
           ```

    - macOS

        1. 你需要一个macOS客户端

        2. 运行构建脚本

           ```bash
           dart .\setup.dart macos --arch <arm64 | amd64>
           ```

## Star History

支持开发者的最简单方式是点击页面顶部的星标（⭐）。

<p style="text-align: center;">
    <a href="https://api.star-history.com/svg?repos=chen08209/FlClash&Date">
        <img alt="start" width=50% src="https://api.star-history.com/svg?repos=chen08209/FlClash&Date"/>
    </a>
</p>