# S1：会话权限默认值与快照

日期：2026-10-20。范围：设置 schema v3、会话 schema v2、启动迁移门槛、设置页默认值、新会话权限快照，以及必要的测试宿主同步。

## 执行与结果

- 格式：绝对路径 Dart SDK `dart.exe format` 对 19 个修改的 Dart 文件执行，通过，0 个文件需要格式化。
- 局部行为与迁移：

  ```powershell
  & 'E:\DevTools\Flutter\bin\flutter.bat' test test/conversation_store_test.dart test/sqlite_migration_coordinator_test.dart test/settings_service_test.dart test/device_preferences_test.dart test/conversation_workspace_test.dart test/settings_page_test.dart --reporter compact
  ```

  在 `app/` 执行，27/27 通过。覆盖 v1 会话库迁移/权限重开持久化，启动协调器的跨库恢复与版本门槛，旧设置和 schema 迁移，便携设置往返/旧格式导入/恢复默认，新会话复制当前默认且已有会话不变，设置页保存默认值。
- 定向静态分析：对 S1 改动的 19 个生产/测试 Dart 文件运行 `& 'E:\DevTools\Flutter\bin\cache\dart-sdk\bin\dart.exe' analyze <上述 S1 文件清单>`，通过，`No issues found!`。实际文件见对应提交和 `git status` 前的修改清单。
- 空白检查：`git diff --check` 通过。

首轮验证遇到并修复：模块文件缺少 `AiPermissions` 直接 import；旧会话迁移测试夹具把新表仅改低 `user_version`，现改为模拟真正没有权限列的旧表；设置页 widget 用例在新增长页面板后滚动到了内层列表，现以扩大专用设置测试视口验证保存路径。最终上述定向测试与分析在当前状态下通过。

## 未执行与边界

未运行全量测试、三端设备矩阵、模型/云盘/语音端到端或构建。S1 只持久化权限状态和默认值；AI 工具执行仍未按权限强制门禁，留待 S5 完成，不能宣称权限闭环已上线。
