# 20 个大型综合场景测试报告

> 日期：2026-10-05
> 主机：Flutter test
> 物理设备：Samsung Galaxy Tab S7 FE，`SM-T736B`，Android 14
> 用例：`app/test/fixtures/large_scenario_20_cases.json`

## 场景范围

固定 20 个大型场景，每个场景包含两轮对话和 6 个结果：

| 场景 | 事项 | 事件 | 待办 | 知识 |
|---|---|---:|---:|---:|
| 大学英语四级考试 | 1 | 2 | 1 | 2 |
| 驾照科目二考试 | 1 | 2 | 1 | 2 |
| 日本关西旅行 | 1 | 2 | 1 | 2 |
| 新房装修项目 | 1 | 2 | 1 | 2 |
| 产品发布项目 | 1 | 2 | 1 | 2 |
| 体检与复诊安排 | 1 | 2 | 1 | 2 |
| 父母体检安排 | 1 | 2 | 1 | 2 |
| 婚礼筹备 | 1 | 2 | 1 | 2 |
| 马拉松训练计划 | 1 | 2 | 1 | 2 |
| 考研报名与初试 | 1 | 2 | 1 | 2 |
| 公司年会项目 | 1 | 2 | 1 | 2 |
| 搬家与地址迁移 | 1 | 2 | 1 | 2 |
| 家庭财务规划 | 1 | 2 | 1 | 2 |
| 宠物绝育与疫苗 | 1 | 2 | 1 | 2 |
| 汽车年检与保养 | 1 | 2 | 1 | 2 |
| 英国访问签证申请 | 1 | 2 | 1 | 2 |
| 创业项目路演 | 1 | 2 | 1 | 2 |
| 社区志愿者活动 | 1 | 2 | 1 | 2 |
| 学期论文与答辩 | 1 | 2 | 1 | 2 |
| 家庭春节聚会 | 1 | 2 | 1 | 2 |
| **合计** | **20** | **40** | **20** | **40** |

总计 120 个自动记录载荷，每个场景的两个事件都有明确开始和结束时间，待办有明确截止时间。

## 测试内容

1. 两轮会话按顺序发送，校验模型响应完成、无错误。
2. 单个场景内 6 个 `create_result` 多工具调用全部处理。
3. 每个事件和待办的时间与预期逐项一致。
4. 每类成果数量正确，正文和标签写入正确。
5. 删除索引后从 Markdown 重建，120 份成果仍完整可见。
6. 同一批测试在主机和 Galaxy Tab 物理设备上分别执行。

## 结果

```text
Host: 21 tests passed
Galaxy Tab S7 FE: 20 scenario tests passed
Scenarios: 20/20
Created result payloads: 120/120
Events: 40/40
Todos: 20/20
Knowledge: 40/40
Matters: 20/20
Markdown rebuild: passed
```

执行命令：

```powershell
cd app
dart run tool/generate_large_scenarios.dart
flutter test test/large_scenario_20_cases_test.dart
flutter test integration_test/large_scenario_20_test.dart `
  -d <device-id>
```

组合入口：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\verify-large-scenarios.ps1 `
  -AndroidDevice <device-id>
```

## 边界

- 本批 20 个场景使用确定性的模拟 SSE / 工具调用，验证应用侧多结果处理、时间字段、持久化和 Markdown 重建。
- 它不验证线上模型对 20 段原始文本的抽取准确率；此前仅对“明天下午三点和客户开会”做了一条真实模型端到端验证。
- 线上模型 20 场景回归需要单独的测试 Key、费用控制和可重试的评分规则。
