# 变更记录

## 1.2.1

- 修正创意工坊简介的标题：原先用的 size=5 不是 Steam 支持的 BBCode 标签（会被原样打印成文字），
  改用 h1 标题标签。
- 修正上传 VDF 的换行：description / changenote 改为写真实换行。steamcmd 不还原字面量 \n，
  1.2.0 上传后工坊页面上整篇简介挤成一行、行间显示 \n。publish.json 的 newlineMode 可切回
  escape（raw 为默认）。
- build 脚本的自检从「VDF 必须是 11 行」换成按 KeyValues 读回并逐字比对 description / title /
  changenote，换行或引号写错时在本地就报错；changenote 现在会接上 CHANGELOG 里的折行。
- mod 内容与 1.2.0 相同，仅工坊页面信息与发布工具链变化。

## 1.2.0

- 补齐创意工坊上传所需文件：`empire_validity_bypass/thumbnail.png`（512×512 纯色占位图，
  `#4B2E83`）与 `descriptor.mod` 里的 `picture="thumbnail.png"`。
- README 增加「创意工坊安装」与「发布到创意工坊」两节，并按上传要求列出检查清单。
- 仓库结构改为标准 Stellaris mod 布局：`empire_validity_bypass.mod` 与 `empire_validity_bypass/`
  直接放在仓库根目录，等价于游戏的 `mod/` 目录（不再有 `mod/` 这一层包装）。
- 新增 `LICENSE`（MIT）与 `empire_validity_bypass/README.txt`（mod 内说明）。
- 起源覆盖脚本使用标准小写扩展名：`common/governments/civics/zzz_empire_validity_bypass_origins.txt`。
- mod 名称改为「虚境铸造：游牧兼容」（`.mod` 与 `descriptor.mod` 同步）。
- 工具链精简为 `tools/install.ps1` 与 `tools/package.ps1`，放在仓库根 `tools/`，不随 mod 分发。

## 1.1.0

- 覆盖定义按 Stellaris 4.5.2 的 `00_origins.txt` 重新对照，保留原版其余全部字段。
- 补充 README（原理、安装、边界说明）与仓库基建（`.gitattributes`、`.gitignore`、`.editorconfig`）。

## 1.0.0

- 初始版本：`zzz_empire_validity_bypass_origins.txt` 覆盖原版 `origin_shroud_forged`，
  从 `possible` 中移除 `is_nomadic = no`，使「虚境铸造 + 游牧」的帝国设计通过合法性校验。

> 1.0.0 / 1.1.0 条目按仓库整理时的状态补写。
