# 变更记录

## 未发布

- `tools/build.*`：把「工坊内容里的描述文件只能是 `descriptor.mod`」从注释变成硬校验——
  源 mod 目录里多出 `<id>.mod` 直接失败（退出码 2）；contentfolder 里出现 `<id>.mod`、
  或 `descriptor.mod` 与源码不是逐字节一致，也判构建失败（退出码 4）。
- 新增 `--local-mod`：在 contentfolder 之外（`build/<id>.mod`）由 `descriptor.mod` 派生一份
  本地安装描述文件，补 `path="mod/<id>"`、去掉启动器补的 `remote_file_id=`；默认不生成，
  工坊上传内容不受影响。
- README 补充描述文件命名规则与 `--local-mod` 用法。

## 1.2.2

- 修复「订阅后启动器显示不兼容、进游戏校验码仍是原版 9776、mod 不生效」：
  `descriptor.mod` / 根部 `.mod` 的 `supported_version` 从 `4.5.*` 改为 **`v4.5.*`**。
- 原因：启动器把 descriptor 的 `supported_version` 原样存成 `requiredVersion`，再与
  `launcher-settings.json` 的 `rawVersion` 比对（该字段的官方说明就是
  "Game version used in validation of mods"）。Stellaris 4.5.2 的 `rawVersion` 是 `v4.5.2`，
  带 `v`；比对规则是「结尾 `.*` → `(?:\..*|)`，其余字面转义，首尾锚定，整串匹配」，于是
  `4.5.*` → `^4\.5(?:\..*|)$` 匹配不上 `v4.5.2`（判不兼容、游戏不加载），
  `v4.5.*` → `^v4\.5(?:\..*|)$` 正常匹配。
- `tools/build.ps1` 增加版本护栏：`supported_version` 必须是 `v<主版本>.<次版本>.*`，
  并读取本机 `launcher-settings.json` 的 `rawVersion` 按启动器同一套规则复验；
  `tools/build.sh` 同步加上同样的格式校验。
- README 补充「订阅后不生效 / 校验码不变」排错一节，并填上创意工坊 ID。

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
