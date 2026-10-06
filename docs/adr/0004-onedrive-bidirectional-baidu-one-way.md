---
status: accepted
---

# OneDrive 双向同步，百度网盘只做单向发布

跨端双向同步只走 OneDrive：App Folder 提供最小权限目录，`/delta` 能给出含删除的增量变更，`eTag` 与 `If-Match` 支持条件写入，MSAL 同时覆盖 Android 与 .NET。百度网盘没有文件级 delta、删除只能靠全量比对、未审核应用配额受限，因此只承担单向发布与冷备，不作为其他端的同步来源。自建服务器（独立主机 + 公网 IP）暂不实现，只在 `SyncProvider` 接口上预留位置。
