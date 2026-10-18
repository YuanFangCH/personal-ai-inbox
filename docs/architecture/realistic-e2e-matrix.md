# 真实端到端测试矩阵（100 条）

本矩阵补充现有「导航 + 单动作」的浅层用例，用多步骤、跨模块、带状态断言的场景验证三端真实使用路径。

## 1. 目标与边界

- 一条场景 = 一个用户可感知的完整任务，6–12 步，至少 2 条状态断言，跨至少 2 个模块。
- 同一份场景数据驱动主机冒烟、两个 Android AVD 腿和 Windows 桌面腿，避免平台间漂移。
- 不替代单元/契约测试，也不连接真实云盘或真实模型 Key。

## 2. 文件与职责

| 文件 | 职责 |
|---|---|
| `app/tool/generate_realistic_scenarios.dart` | 场景生成器；确定性输出，生成后自动 `dart format` |
| `app/test/e2e/realistic_scenarios.g.dart` | 100 条场景数据（生成文件，入库可审阅） |
| `app/test/e2e/realistic_scenario.dart` | 场景/步骤模型、支持的 op 与断言清单 |
| `app/test/e2e/realistic_runner.dart` | 生产组合根装配、步骤执行、断言、脚本化模型与同步通道 |
| `app/test/e2e/realistic_matrix_integrity_test.dart` | 矩阵完整性（数量、分布、复杂度、op/断言合法性） |
| `app/test/e2e/realistic_host_smoke_test.dart` | 主机冒烟：每个分类 1 条，CI 可跑 |
| `app/integration_test/realistic_100_android_test.dart` | Android 腿，按 `--dart-define=E2E_PLATFORM=phone\|tablet` 过滤 |
| `app/integration_test/realistic_100_windows_test.dart` | Windows 桌面腿 |
| `scripts/verify-realistic-e2e.ps1` | 启动/回收 AVD、执行三条腿、汇总日志 |

## 3. 场景分布

| 分类 | 条数 | 覆盖点 |
|---|---|---|
| capture | 12 | 中文相对时间、周内日期、截止时间、无效日期、知识兜底 |
| review | 10 | 低置信进待整理、按建议生成、忽略、后续新建 |
| calendar | 12 | 年/月/周/日/日程列表、事件与待办投影、快速新建、勾选 |
| matters | 8 | 事项详情、子项归属、追加日程、勾选联动 |
| knowledge | 8 | 60 条批量、中文检索、详情、分页加载 |
| chat | 12 | 文本回复、工具自动建成果、撤销 |
| chatFailure | 6 | HTTP 失败与重试、缺少 `[DONE]`、用户停止 |
| sync | 10 | 空通道、远端新增、双端冲突、两种裁决 |
| persistence | 6 | 真实文件 vault + 冷启动重建索引 |
| settings | 8 | 主题往返、图片出网开关、保存后生效 |
| recovery | 4 | 整理中关闭后重启转待确认 |
| mixed | 4 | 捕获、日历、同步、重启连续流程 |

平台分配：手机 50、平板 25、Windows 25。

## 4. 步骤 DSL

用户可见操作：`nav`、`capture`、`calendarMode`、`calendarSection`、`quickCreate`、`toggleTodo`、`openDoc`、`searchKnowledge`、`newChat`、`startChat`、`retryChat`、`stopChat`、`undoAutoRecord`、`tapText`、`sync`、`resolveConflict`、`theme`、`imageEgress`、`restart`、`scroll`。

夹具操作：`seed`（mixed / matterTree / knowledgeBulk / processingCapture）、`assert`。

断言：`resultCount`、`typeCount`、`titleExists`、`titleMissing`、`reviewCount`、`conflictCount`、`textVisible`、`bodyContains`、`todoDone`、`themeDark`、`imageEgress`、`conversationCount`、`chatReplyContains`、`assistantStatus`、`noException`。

## 5. 执行

```powershell
# 主机冒烟（1 条/分类）
cd app
flutter test test/e2e/realistic_host_smoke_test.dart

# 三端全量（自动启动/回收 AVD）
powershell -ExecutionPolicy Bypass -File .\scripts\verify-realistic-e2e.ps1

# 单腿
powershell -ExecutionPolicy Bypass -File .\scripts\verify-realistic-e2e.ps1 -Platforms phone
```

日志写入 `app/build/realistic-e2e/<timestamp>/`，不进入 Git。

## 6. 稳定性规则

- 模型：`MockClient.streaming` 脚本化 SSE；按请求体 `stream` 字段区分流式对话与分类请求。
- 同步：`ScriptedSyncProvider` 支持播种、覆盖与 eTag 条件写，冲突可复现。
- 时间：场景日期用 `{{future:N}}` / `{{past:N}}` 令牌在运行时解析，断言不依赖具体日期。
- 存储：默认内存 adapter 保证隔离；持久化分类使用真实文件 vault，索引在冷启动时从 Markdown 重建。
- 主机限制：`testWidgets` 的 fake async 不驱动真实文件 IO，因此持久化分类只在三条设备腿运行，主机用 recovery 分类覆盖冷启动语义。

## 7. 2026-10-18 执行结果

| 腿 | 结果 | 用例耗时 |
|---|---|---|
| 主机全量套件 | 376/376 通过 | 36 s |
| 主机矩阵预跑（除持久化） | 94/94 通过 | 46 s |
| Android 手机 AVD（Pixel 6） | 50/50 通过 | 8 min 10 s |
| Android 平板 AVD（2560×1600） | 25/25 通过 | 4 min 27 s |
| Windows 桌面（1440×900 逻辑视口） | 25/25 通过 | 3 min 11 s |

## 8. 本轮发现并修复

- `StatusPill` 在手机 1.15x 字体下横向溢出 7.1px：标签改为单行省略，补 `status_pill_test.dart` 回归。
- 设置页主题与图片开关为暂存值：场景改为点击「保存」后再断言持久化结果。
- 知识检索在滚动后文本输入焦点丢失：先回到输入框并显式聚焦再输入。
- 同步冲突、自动记录撤销、跨重启持久化均已由端到端场景覆盖。
