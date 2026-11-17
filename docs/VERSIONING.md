# 版本与数据兼容策略 / Versioning & Data Compatibility

## 版本号

`MAJOR.MINOR.PATCH`（`project.yml` 的 `MARKETING_VERSION`，构建号在 `CURRENT_PROJECT_VERSION`）。
1.0.0 为本地功能完整版本。

## 数据库

- 位置：`~/Library/Application Support/TinyTodo/TinyTodo.sqlite`（WAL）。
- 迁移由 GRDB `DatabaseMigrator` 管理，迁移标识写入 `grdb_migrations` 表。
- 规则：**只增不改**。新版本只能添加表、列（带默认值）、索引；不得删除 `todos` 行、
  不得重写 `completed_at`、不得清空历史。
- 当前版本：

| 版本 | 内容 |
| --- | --- |
| v1 | `todos` 表 + `idx_todos_status` + `idx_todos_completed_at` |
| v2 | `idx_todos_title`（历史搜索） |
| v3 | `idx_todos_pending_order`（待办排序覆盖索引） |

- 升级流程：启动时 `DatabaseMigration.migrator.migrate(dbQueue)`；已应用的迁移会跳过，
  重复启动是幂等的（测试 `testUpgradeFromV1PreservesHistoryRows` 覆盖 v1 → v3 并二次迁移）。

## 备份格式

`ExportFile`：`app`、`version`（当前 1）、`exportedAt`、`todos[]`。
时间使用 ISO-8601（UTC，含毫秒）。导入按 `id` upsert，不删除现有数据；
`version > 1` 直接拒绝，避免旧客户端误读新字段。空标题行计入 `skipped`。

## 理性回滚

- 回滚到旧版本时数据库可能包含更多索引（旧版本会忽略），数据行格式兼容 v1。
- 若必须破坏性变更：先导出 JSON，再发布新的 major 版本，并在 CHANGELOG 中说明。

## 公证与分发

`scripts/make_dmg.sh` 使用 ad-hoc 签名，便于本地/CI 产物直接打开。正式分发：
替换为 Developer ID Application 证书 → `codesign --deep --options runtime` →
`xcrun notarytool submit` → `stapler staple`。Sparkle 自动更新留待后续版本。
