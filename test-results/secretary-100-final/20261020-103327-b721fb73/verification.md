# 混合代码的诊断运行（不计入验收）

- 脚本：`scripts/verify-secretary-e2e.ps1 -Platforms all`，清单起始 SHA 为 `b721fb731c03cea25d6ff50ee6873be495c859fe`，脚本启动时工作树干净。
- 汇总：100 IDs，phone 50、tablet 25、Windows 25；97 passed、3 failed、0 not executed。失败为 SEC-010、SEC-083、SEC-089。
- 有效性：运行期间根据手机 AVD 暴露的问题继续修改了源文件。phone 测试 APK 在这些修改前编译；tablet 和 Windows Runner 在后续构建，不能证明各腿来自同一源码状态。此目录只保留诊断日志，不作为候选 SHA 的通过/失败结论，也不满足 S12。
- 诊断修复：SEC-010 使用的测试 PNG 无法解码，已换成生成的有效 PNG；SEC-083 follow-up 断言取错了跨会话消息顺序并改为按新会话断言；SEC-089 加入离开对话页后取消请求并验证日历页状态。
- 需要动作：提交修复后在新干净 SHA 上重新执行完整 50/25/25。
