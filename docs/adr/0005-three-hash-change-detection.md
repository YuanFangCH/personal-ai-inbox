---
status: accepted
---

# 用三项 hash 判断变更，时钟只用于破平局

每个成果在 frontmatter 里带 `revision`、`origin_device`、`updated_at`，同步端另存上次同步成功时的 `last-synced-hash`。判定顺序是：远端 hash 等于上次同步值说明远端没动，直接快进；本地 hash 等于上次同步值说明本地没动，直接接受远端；两边都变了才算真冲突，交给冲突副本与确认队列。只有裁决真冲突时才用到 `updated_at`，仍相同再按 `device_id` 字典序破平局，因此不依赖任何一台设备的时钟准确，也不引入向量时钟。
