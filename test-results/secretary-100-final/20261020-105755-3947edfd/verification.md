# S12 终轮诊断（停止于 SEC-083）

- 候选 SHA：`3947edfd273ad7a9367479d71b0942e784890b21`，启动时 manifest 记录工作树干净。
- 运行在 phone AVD 执行到 SEC-083 时，停止后继续输入没有重新建立文本输入焦点，后续请求未提交；Runner 在停止后增加显式聚焦和泵帧。当前 phone 日志中 46 条 SEC_CASE_RESULT passed、SEC-083 失败，余下 phone 3 例及 tablet/Windows 未运行；脚本被停止后没有 summary.json。
- 单例修复探针：phone AVD SEC-083 以修改后的 Runner 执行 1/1 通过（两个模型请求）；报告在 `test-results/secretary-s12-runner-hardening-device/20261020-110137-3947edfd/cases/SEC-083.json`。该探针工作树含未提交修改，只作诊断。
- 本目录仅保留失败运行的 manifest、phone 信息和日志。不是 100 例结果；最终必须在提交显式输入聚焦修复后再次干净启动全部三端矩阵。
