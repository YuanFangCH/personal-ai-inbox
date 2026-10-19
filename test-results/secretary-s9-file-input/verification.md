# S9 本地文件输入与解析验证

- 日期：2026-10-20（Asia/Singapore）
- 改动：使用 `file_picker` 原生选择 Android/Windows/Web 文件；本端读取/解析 TXT、MD、CSV、DOCX、XLSX 和有文字层的 PDF；只把提取文字与文件名并入用户消息，原始文件字节不保存或发往模型。
- 安全边界：每文件最多 8 MiB；每条消息最多 3 个文件和 24,000 Unicode 字符；DOCX/XLSX ZIP 最多 256 entries、展开总量 24 MiB、单 entry 8 MiB；XLSX 最多 12 张工作表/每表 200 行/5000 单元格；PDF 最多 50 页。宏不执行，公式不执行，仅显示缓存值/标记公式；扫描 PDF 无文字层时明确提示暂不支持 OCR。文件内容按不可信资料交给模型。
- 执行：从 `app/` 运行 `E:\DevTools\Flutter\bin\flutter.bat test test/file_input_service_test.dart test/secretary_file_attachment_ui_test.dart --reporter expanded`。
- 结果：通过，9/9。覆盖选择注入/取消、UTF-8 BOM、Unicode 字符限制、CSV、DOCX XML、XLSX shared strings 与未执行公式、PDF文字/扫描件分支、类型/大小/预算校验及对话文本请求不含原始二进制。
- 执行：对 `file_input_service.dart`、`chat_service.dart`、对话页面/composer及相关测试执行 `dart analyze`，无问题。
- 执行：`flutter build apk --release`、`flutter build windows --release`、`flutter build web --release`：均成功。Windows 本地 Developer Mode 已启用，满足 PDFium native asset 的构建要求。
- 未执行：Android/Windows 原生文件选择器真实 UI 操作、PDFium 读取真实 PDF 文件的设备探针、扫描 PDF OCR、真实模型 Key、三端 SEC-001–100 和全项目全量测试。UI/解析测试注入确定性文件 picker/PDF 文本端口，不能冒充真实设备与 PDFium 解码证据。
- 技术依据：[`file_picker` 官方 API/平台兼容表](https://pub.dev/packages/file_picker)、[`pdfrx` PDFium 多平台/Windows 要求](https://pub.dev/packages/pdfrx)、[`pdfrx_engine` 页面文字 API](https://pub.dev/documentation/pdfrx_engine/latest/pdfrx_engine/PdfPage-class.html)。
