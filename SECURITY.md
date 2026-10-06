# 安全策略

## 支持范围

安全修复只针对 `main` 分支的最新版本。发布版本可能同时存在于开发分支，但修复会优先合入 `main`。

## 报告安全问题

请不要在公开 Issue 中粘贴 API Key、OAuth 令牌、密码、签名文件、本地 vault、消息附件或设备序列号。优先使用 GitHub 仓库的 Private vulnerability reporting 或 Security Advisory 私下报告，并只提供复现所需的最小信息。

报告时建议包含：

- 受影响版本或提交；
- 问题类型和影响范围；
- 最小复现步骤；
- 是否已经导致数据或凭据暴露；
- 可用的缓解方法。

## 凭据处理

- API Key 和 OAuth 令牌只允许存放在 Android Keystore、Windows Credential Manager 或其他系统安全存储中。
- 不要把密钥写入代码、配置文件、Markdown、日志、文件名、URL、测试夹具或截图。
- Android/iOS 签名文件、`key.properties`、`.env*`、本地 vault 和构建产物均不得提交。
- 如果密钥曾被提交或推送，应立即在提供商侧撤销并轮换，然后清理 Git 历史。只删除当前文件不能使密钥失效。

## 维护者响应

确认报告后会评估影响、修复 `main` 并说明是否需要用户轮换凭据。未确认前不会公开披露可被直接利用的细节。
