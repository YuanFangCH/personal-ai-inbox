# v1.1.3 预览版发布验证

## 首次 GitHub Release 工作流

- 运行：GitHub Actions `Release`，[39410047857](https://github.com/YuanFangCH/personal-ai-inbox/actions/runs/39410047857)，标签 `v1.1.3` 指向 `736e603f1f92c23c60343c712087fa2b3d8c31e3`。
- 通过：标签与 `app/pubspec.yaml` 版本一致；Dart 格式检查；`flutter analyze`。
- 失败：完整 `flutter test --reporter expanded` 中 3 项测试仍引用旧页面流程；Android/Windows Release 构建、安装器冒烟和资产发布因测试失败而未执行。
  - `android_ui_090 inbox 页主要按钮点击检查`：旧测试查找已从收件箱移除的“收下内容”按钮。
  - `e2e_013 待整理项按建议生成：记住：英语比赛在下周三`：待整理入口已改为独立“待处理”页面。
  - `e2e_071 双端修改产生冲突并采用远端`：同步冲突入口同样迁入独立“待处理”页面。

## 修复与定向验证

- 修改长期回归测试，让收件箱按钮检查打开新对话；生成的场景由对话侧栏进入待处理；Material 路由通过 Flutter back-route 接口返回。
- 通过：
  - `flutter test test/android_ui_100_cases_test.dart --plain-name 'android_ui_090' --reporter expanded`：1/1。
  - `flutter test --no-pub test/e2e/realistic_host_smoke_test.dart --plain-name 'e2e_013' --reporter expanded`：1/1。
  - `flutter test --no-pub test/e2e/realistic_host_smoke_test.dart --plain-name 'e2e_071' --reporter expanded`：1/1。
- 完整发布门禁尚未重跑；更新后的 `v1.1.3` 发布标签与资产待确认。
