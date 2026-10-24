# 变更记录

## 1.2.0

- 补齐创意工坊上传所需文件：`empire_validity_bypass/thumbnail.png`（512×512 纯色占位图，
  `#4B2E83`）与 `descriptor.mod` 里的 `picture="thumbnail.png"`。
- README 增加「创意工坊安装」与「发布到创意工坊」两节，并按上传要求列出检查清单。
- 仓库结构改为标准 Stellaris mod 布局：`empire_validity_bypass.mod` 与 `empire_validity_bypass/`
  直接放在仓库根目录，等价于游戏的 `mod/` 目录（不再有 `mod/` 这一层包装）。
- 新增 `LICENSE`（MIT）与 `empire_validity_bypass/README.txt`（mod 内说明）。
- 起源覆盖脚本使用标准小写扩展名：`common/governments/civics/zzz_empire_validity_bypass_origins.txt`。
- mod 名称改为「虚境锻造：游牧兼容」（`.mod` 与 `descriptor.mod` 同步）。
- 工具链精简为 `tools/install.ps1` 与 `tools/package.ps1`，放在仓库根 `tools/`，不随 mod 分发。

## 1.1.0

- 覆盖定义按 Stellaris 4.5.2 的 `00_origins.txt` 重新对照，保留原版其余全部字段。
- 补充 README（原理、安装、边界说明）与仓库基建（`.gitattributes`、`.gitignore`、`.editorconfig`）。

## 1.0.0

- 初始版本：`zzz_empire_validity_bypass_origins.txt` 覆盖原版 `origin_shroud_forged`，
  从 `possible` 中移除 `is_nomadic = no`，使「虚境锻造 + 游牧」的帝国设计通过合法性校验。

> 1.0.0 / 1.1.0 条目按仓库整理时的状态补写。
