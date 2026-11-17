# v1.6.3 Android 预览版验收结果

日期：2026-11-17（Asia/Singapore）

## 结论

- **通过**：GitHub Flutter CI #61（`44002023767`）和 Android Release #`44002331180` 均成功；格式、Analyze、发布回归、Release APK 构建与签名/API/版本门禁通过。
- **通过**：公开 prerelease [phone-v1.6.3](https://github.com/YuanFangCH/personal-ai-inbox/releases/tag/phone-v1.6.3) 可下载。公开下载 APK 的 SHA-256 `db4ba5da0f10113b43ab5b0235a41c4484a63ba152c2d41d8570ed1e1d0005e6` 与 GitHub `SHA256SUMS.txt` 一致，也与先前核验的 Release 草稿 APK 相同。APK 元数据：`1.6.3+17`、minSdk 24、targetSdk 36、非 debuggable、v2 签名；证书 SHA-256 `51b5e2f3f44ce9374cb680a0173c6498a4e13c718c602a355a8b6a50523f4816`。
- **通过**：D 盘 API 35 AVD 上指令编辑集成测试（1/1）：打开设置和 AGENTS.md 页面、Vault 保存/读回、撤销移除；冷启动 UI 读回也通过。页面 SafeArea 与 Material 祖先缺陷均已修复。
- **通过**：旧版覆盖升级。合成旧全局知识 `V163_legacy` 在旧版中经界面创建；安装 1.6.3 Release APK 后包版本为 1.6.3、`firstInstallTime` 仍为 `2026-11-16 05:06:12`。新版本归档预览显示 1 条旧知识、1 条待处理记录、0 条冲突副本。确认后计数均为 0；AGENTS.md 编辑器保持空白，旧知识未自动迁入。
- **通过**：设备导出 `legacy-global-knowledge.zip`；ZIP 含旧知识 Markdown、`candidates.json`、`manifest.json`。逐项重算 manifest 中两份源的 SHA-256，均匹配 ZIP 实际条目。
- **通过**：D 盘 256 MiB 写入、刷盘、回读 SHA-256 预检；Android SDK、AVD、构建缓存、临时目录、APK 和证据均位于 D 盘，未将模拟器或测试产物放到 C 盘。

## 关键命令与来源

```powershell
flutter test integration_test/agent_instructions_phone_test.dart -d emulator-5620 --no-pub --reporter expanded
gh run view 44002023767
gh run view 44002331180
gh release download phone-v1.6.3 --dir D:\DevTools\Android\aitext-validation\phone-v1.6.3\public-release --clobber
Get-FileHash -Algorithm SHA256 D:\DevTools\Android\aitext-validation\phone-v1.6.3\public-release\personal-ai-inbox-v1.6.3-android.apk
```

Windows 本地 `flutter test test/settings_page_test.dart` 因缺少 `Microsoft.VisualStudio.Component.VC.Tools.x86.x64` 在 PDFium hook 阶段不能启动；相关发布定向回归已由 GitHub CI #61 执行通过。模拟器升级证据、UI 树、截图、导出 ZIP 与公开下载副本位于 `D:\DevTools\Android\aitext-validation\phone-v1.6.3\upgrade`（公开下载文件位于其 `public-release` 子目录）。

## 未覆盖范围

荣耀 90 真机、API 24–30 固定行、Android 平板、Windows UI、真实用户旧数据及真实模型/云同步未在本轮覆盖。旧知识归档仅用模拟器合成数据验证。
