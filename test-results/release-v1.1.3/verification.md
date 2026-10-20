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
- 三个定向修复用例通过后，更新标签并重新触发完整发布门禁；正式结果见下节。

## 正式发布结果

- 通过：GitHub Actions [Release workflow 39411172444](https://github.com/YuanFangCH/personal-ai-inbox/actions/runs/39411172444)，总耗时 16m41s；标签指向 `e6ebb7ae5eb141adef07885cedb5e424b577bfb9`。
- 格式、静态分析、完整主机测试 `flutter test --reporter expanded`（521 项）、Android Release、Windows Release、APK 元数据/证书、Inno Setup 安装与卸载冒烟、便携 ZIP 检查和发布步骤全部通过。
- GitHub Release [懒狗秘书 v1.1.3](https://github.com/YuanFangCH/personal-ai-inbox/releases/tag/v1.1.3) 已发布，`draft=false`、`prerelease=true`，包含四项资产：
  - APK：87,219,931 bytes，SHA-256 `9ddd9b4ee0aa2dc139fde21091a76702fcfbb9b4922747b9a881800f12b9dd6c`
  - Windows 安装包：15,483,775 bytes，SHA-256 `6f03ac957716b87185d1279f96eb61c7c2830038cd8a2303dad6c32d99893772`
  - Windows 便携包：19,056,278 bytes，SHA-256 `3479f274572d034f75a3d86add6c9fa2a54ba8dc1d4fd072789e815f882b02c9`
  - `SHA256SUMS.txt`：已下载并逐项与 GitHub API 的三个资产 digest 对照，全部匹配。
