# Widget timeline validation

Date: 2026-11-12 (Asia/Singapore)

## Passed

- `flutter analyze --no-pub` on the nine affected Dart files: no issues.
- `flutter test --no-pub --reporter expanded test/home_widgets/home_widget_projection_test.dart test/home_widgets/home_widget_contract_test.dart test/home_widgets/widget_workspace_test.dart test/home_widgets/widget_store_test.dart test/widget_tools_test.dart test/home_widget_bridge_test.dart`: 31 tests passed. Coverage includes time filtering, cross-table merge/deduplication, 48-row and 512 KiB trimming, title/detail privacy, legacy configuration, authorization, storage, secretary tools, and the bridge.
- `flutter build apk --debug --no-pub`: passed after restoring the existing lockfile dependencies with `flutter pub get`. The lockfile and dependency declarations were unchanged.
- `git diff --check`: passed.

## Failed or not verified

- `flutter test --no-pub --reporter expanded test/home_page_ui_test.dart test/app_runtime_test.dart`: `app_runtime_test` migration case passed; four `home_page_ui_test` cases failed during test teardown because `AgentBackgroundLifecycleGate.scheduleShutdown` leaves its existing two-second timer pending. The test assertions ran; this run does not establish a clean UI test result.
- An initial APK install on `emulator-5620` was rejected because the existing app has a different signing certificate. The installed app was left intact. A clean API 35 AVD was started, but its ADB transport did not become available during this run.
- API 35 widget rendering, launcher paging/taps, independent widget instances, and upgrade preservation were not verified in this run. API 24–30 and Honor 90 were also not verified.
- Full test suite and release/publish were not run.

## Commands

```powershell
flutter analyze --no-pub lib/core/table_entry_order.dart lib/ui/pages/home_page.dart lib/ui/pages/table_detail_page.dart lib/modules/home_widgets/home_widget_contract.dart lib/modules/home_widgets/home_widget_projection.dart lib/modules/home_widgets/widget_workspace.dart lib/ui/pages/widget_settings_page.dart lib/services/widget_tools.dart lib/services/chat_service.dart

flutter test --no-pub --reporter expanded test/home_widgets/home_widget_projection_test.dart test/home_widgets/home_widget_contract_test.dart test/home_widgets/widget_workspace_test.dart test/home_widgets/widget_store_test.dart test/widget_tools_test.dart test/home_widget_bridge_test.dart

flutter test --no-pub --reporter expanded test/home_page_ui_test.dart test/app_runtime_test.dart

flutter build apk --debug --no-pub
```
