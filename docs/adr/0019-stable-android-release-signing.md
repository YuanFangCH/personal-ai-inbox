---
status: accepted
---

# Android 预览发布固定长期签名

从 `v1.1.4` 起，Android Release APK 使用专用、长期保存的签名密钥。本机私钥保存在仓库外并备份，GitHub Actions 通过 Secrets 注入；密钥不得提交到源码仓库。发布工作流校验 APK 证书 SHA-256 指纹，不匹配时失败。

`v1.1.3` 及之前由不同构建环境生成的 Debug 密钥不保证一致，无法用新密钥覆盖安装。新密钥丢失会破坏后续 Android 更新兼容性，因此必须备份并限制访问。
