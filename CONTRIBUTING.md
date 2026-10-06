# 贡献指南

感谢参与改进项目。请先阅读 [CONTEXT.md](CONTEXT.md)、[可执行方案](docs/personal-ai-inbox-executable-plan.md)、[同步协议](docs/sync-protocol.md) 和 [模型接入](docs/model-integration.md)，保持术语、数据契约和安全边界一致。

## 开发环境

```powershell
cd app
flutter pub get
flutter run
```

提交前至少执行：

```powershell
flutter analyze
flutter test
```

涉及构建、Android 分享入口、Windows 原生能力或同步逻辑时，请补充对应平台验证或明确说明未执行项。

## 代码与文档

- 使用仓库现有 Flutter 分层和本地命名，不引入无必要的框架或抽象。
- 修改数据格式、同步语义、模型边界或公开接口时，同步更新方案、协议或 ADR。
- 一个成果一个 Markdown 文件、冲突保留副本、删除留墓碑、会话不出端等不变量不得绕过。
- 不要提交生成的 `build/`、`.dart_tool/`、签名文件、环境文件或本地数据。

## 提交要求

提交标题使用 Conventional Commits：

```text
feat(app): 增加某个能力
fix(sync): 修复某个问题
docs: 更新文档
chore(repo): 调整仓库配置
```

允许的类型：`chore`、`docs`、`feat`、`fix`、`refactor`、`test`、`build`、`ci`、`perf`、`revert`。

## 安全

不要提交真实凭据。示例只使用明显的占位值，例如 `<API_KEY>`。如果发现真实密钥已进入仓库，请按 [SECURITY.md](SECURITY.md) 处理，不要在公开 Issue 中复述密钥。
