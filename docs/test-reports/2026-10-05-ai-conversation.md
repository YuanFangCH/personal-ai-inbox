# AI 多会话与自动记录验证报告

> 验证对象：收件箱多会话、上下文隔离、图片输入与自动记录
> 日期：2026-10-05
> 设备：`aitext_honor_phone` AVD，Android 15 x86_64，1080x2400 / 420dpi
> 构建：Flutter Android debug / release、Web release

## 实现范围

- 收件箱增加本地多会话列表，保留原有待确认捕获与草稿。
- 应用冷启动创建并打开一个持久化空白会话；切换标签和应用回前台不重复创建。
- 会话支持文本、剪贴板粘贴、相册、拍照和 Android 文本 / 图片分享入口。
- 模型回复通过 OpenAI 兼容 SSE 流式显示，可停止并保留半成品。
- 每次只发送当前会话最近 20 条消息，图片来自最近 4 条含图消息且不超过 8 张。
- 模型可通过 `create_result` 自动新建高置信、非敏感成果；风险项进入待整理，成功创建后支持 10 分钟撤销。
- 会话、消息、自动记录审计和图片只保存在本端，不进入 Markdown 成果同步。

## 自动化验证

- `flutter analyze`：通过，无 warning、error 或 lint issue。
- `flutter test -r compact`：231 项全部通过。
- 新增专项测试：
  - SQLite 会话、消息、附件元数据和自动记录动作持久化。
  - OpenAI 兼容 SSE 内容与工具调用分片解析。
  - 高置信自动创建、低置信待整理、10 分钟撤销和跨会话上下文隔离。
  - 冷启动只创建一个空白会话并自动打开聊天页。
- `flutter build apk --debug`：通过。
- `flutter build web --release`：通过。
- `flutter build apk --release`：通过，APK 约 63.4 MB；SHA-256 `C4CFC1B5079FD0B7D7483138ADD266A3702AD98399D9F0503647A07473C6C99D`。

## AVD 人工探针

- Release APK 覆盖安装后冷启动直接打开“新对话”，标题包含本地时间。
- 未配置模型时聊天输入、粘贴和图片入口禁用，并显示配置提示。
- `ACTION_SEND text/plain` 从运行中的模拟器投递后，新建会话、保存用户消息并打开聊天页。
- 官方 Android Photo Picker 可从应用内打开、选择图片并返回输入栏预览。
- 设置页的图片出网开关存在且默认开启；测试用临时 Key 已在验证后清除。

## 未完成验证

- 未使用真实 API Key 执行线上 SSE、工具调用和自动创建端到端验证；当前使用 Mock HTTP 覆盖协议。
- ADB 从 `shell` 直接投递 `content://` 图片时无法代替媒体 URI 所有者授予读权限，因此未把该命令作为外部图片分享通过证据；应用内 Photo Picker 已通过。
- 相机拍照和真实第三方 App 分享图片仍需物理设备或人工操作验收。
