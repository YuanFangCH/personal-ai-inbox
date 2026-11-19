# v1.6.4 Android 手机预览版验证

- Git 标签 `phone-v1.6.4` 指向 `4f8caed`。GitHub [main CI](https://github.com/YuanFangCH/personal-ai-inbox/actions/runs/44503312733) 和 [Android Release](https://github.com/YuanFangCH/personal-ai-inbox/actions/runs/44503312635) 均成功。
- Release 先生成草稿，经签名与升级确认后，使用 `gh release edit phone-v1.6.4 --draft=false --prerelease --latest=false` 公开。通过 `gh release download` 分别下载草稿与公开资产，`Get-FileHash -Algorithm SHA256` 实算均与 `SHA256SUMS.txt` 一致。
- 公开 APK 共 92,697,759 字节。SHA-256 为 `9558c124fae28a919723b1349eb2b37698044d9786e76500a6713939084f2ec7`。
- `apksigner verify --verbose --print-certs` 确认 APK Signature Scheme v2 校验通过，唯一签名者为项目长期发布证书，证书 SHA-256 为 `51b5e2f3f44ce9374cb680a0173c6498a4e13c718c602a355a8b6a50523f4816`。
- `aapt2 dump badging` 确认 apk 为 `com.yuanfang.aitext.personal_ai_inbox`、`1.6.4+18`、最低 API 24、目标 API 36、非 debuggable，包含 arm64-v8a、armeabi-v7a 和 x86_64。
- API 35 AVD 使用 `adb -s emulator-5560 install -r` 从 1.6.3+17 覆盖安装，`dumpsys package` 显示版本升至 1.6.4+18，首次安装时间保持一致。
- 升级前创建合成桌面卡片 `PreviewSmoke` 及带时间的待办 `PreviewTimedTodo`。升级后通过启动器 UI 树确认保留绑定、呈现 `ListView` 且默认仅显示标题。点击该行打开对应待办编辑页，标为已完成并保存后直接返回桌面，卡片自动显示「暂无内容」。
- 设备端本轮未验证多行滚动、详细模式、大字体、深色主题、冷进程点击、API 24–34、真机及平板。实现阶段定向测试见 [验证记录](../home-flat-timeline-20261119/VALIDATION.md)。
