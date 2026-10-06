---
status: accepted
---

# 三端统一用 Flutter

手机、平板、Windows 三个客户端共用一套 Dart 代码与共享核心，只在平台壳上分化。选择 Flutter 而不是 .NET MAUI、Tauri 或纯原生，是因为三端里有两端是 Android，而分享接收、本地通知、后台调度这些最高频的能力在 Flutter 上插件最成熟；Windows 端的托盘、热键与 Toast 也有现成方案。代价是 Windows 客户端的原生观感弱于 MAUI，但换掉的是 Android 分享入口的开发与维护成本。
