# 虚境铸造：游牧兼容 — Stellaris 起源合法性兼容 mod

一个只改一条规则的小 mod：让「虚境铸造（Shroud-Forged）」起源不再排除游牧，从而让
同时带 `is_nomadic=yes` 与 `origin="origin_shroud_forged"` 的帝国设计通过起源合法性校验。

- 游戏版本：**Stellaris 4.5.x**（开发与验证于 4.5.2 Cygnus）
- 依赖 DLC：**Shadows of the Shroud**
- 本地化：**无新增文本**（只改判定逻辑，界面上不出现新词条）
- 当前版本：见 [`empire_validity_bypass/descriptor.mod`](empire_validity_bypass/descriptor.mod)
- 创意工坊：`https://steamcommunity.com/sharedfiles/filedetails/?id=<PublishedFileId>`（上传后把 ID 填在这里）

## 安装

### 方式 A：创意工坊（推荐）

1. 打开发布页点「订阅」。Steam 会把内容下载到
   `<Steam>\steamapps\workshop\content\281990\<PublishedFileId>\`。
2. 启动 Paradox 启动器 —— 它会在 `Documents\Paradox Interactive\Stellaris\mod\` 自动生成
   `ugc_<PublishedFileId>.mod`，在播放集里勾选 **虚境铸造：游牧兼容**。
3. 启动游戏。

订阅式安装不需要解压任何文件：更新由 Steam 自动完成，取消订阅即卸载。

> 不要同时保留本地安装版，否则启动器里会出现两个同名条目。

### 方式 B：本地安装（未订阅 / 改过源码）

1. 下载本仓库（Code → Download ZIP）并解压。
2. 把 `empire_validity_bypass` 文件夹 **和** `empire_validity_bypass.mod` 文件一起复制到
   `Documents/Paradox Interactive/Stellaris/mod/`。
3. 在 Paradox 启动器里启用 **虚境铸造：游牧兼容**。

更新时先删掉旧的 `empire_validity_bypass` 文件夹再复制，避免残留旧文件。

### 方式 C：脚本安装

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\install.ps1 -Enable
```

会备份旧副本、写出带绝对路径的 `.mod`，并把条目追加到 `dlc_load.json`。

## 它改了什么

| 字段 | 原版 | 本 mod |
| --- | --- | --- |
| `possible` 里的 `is_nomadic = no` | 有 | 去掉 |
| 权威要求 | `auth_machine_intelligence` | 不变 |
| 排除的公民 | `servitor` / `terminator` / `assimilator` / `chosen` | 不变 |
| DLC 要求 | `has_shroud_dlc = yes` | 不变 |
| 图标、`max_once_global`、特质点数加成等 | 原版值 | 不变 |

覆盖原理：`common/governments/civics` 是 LIOS（last-in, only-served，后加载覆盖先加载）。
文件名 `zzz_empire_validity_bypass_origins.txt` 的 `zzz_` 前缀保证它排在原版
`00_origins.txt` 之后加载，于是同名的 `origin_shroud_forged` 条目覆盖原版定义。

## 仓库结构

```text
stellaris/                                   # 等价于游戏目录下的 Stellaris/mod/
├─ empire_validity_bypass.mod                # 本地安装用描述文件（含 path="mod/empire_validity_bypass"）
├─ empire_validity_bypass/                   # mod 本体 = 工坊上传的内容
│  ├─ descriptor.mod                         # 工坊上传用描述文件（不含 path）
│  ├─ thumbnail.png                          # 512×512 预览图（当前为纯色占位图）
│  ├─ README.txt                             # 给只拿到 mod 文件夹的人看的说明
│  └─ common/governments/civics/
│     └─ zzz_empire_validity_bypass_origins.txt    # 唯一实际改动
├─ tools/                                    # 开发脚本（不进游戏目录、不进工坊上传）
│  ├─ common.ps1
│  ├─ install.ps1
│  ├─ package.ps1
│  ├─ build.bat                              # 纯 ASCII 启动器，转调 build.ps1（Windows）
│  ├─ build.ps1                              # 提取上传集合 + 渲染 VDF 的实现
│  └─ build.sh                               # 同上（Linux / macOS / Git Bash）
├─ build/                                    # build 脚本产物，不入库
│  ├─ empire_validity_bypass/                #   ← 创意工坊的 contentfolder
│  └─ workshop_build_item.vdf                #   ← steamcmd 上传参数（不随内容上传）
├─ CHANGELOG.md
├─ LICENSE
├─ README.md
└─ .gitattributes  .gitignore  .editorconfig
```

根目录的 `<id>.mod` + `<id>/` 与游戏 `mod/` 目录一一对应，整个仓库可以直接当作
`Stellaris/mod/` 使用；工坊上传时只上传 `empire_validity_bypass/` 这个文件夹。

## 发布到创意工坊

上传前先确认 mod 文件夹里的三件事：

| 项 | 要求 | 当前状态 |
| --- | --- | --- |
| `empire_validity_bypass/descriptor.mod` | 含 `version` / `tags` / `name` / `picture` / `supported_version`，**不要**写 `path` | ✅ |
| `empire_validity_bypass/thumbnail.png` | 正方形预览图，512×512 为惯例 | ⚠️ 纯色占位图（`#4B2E83`），正式发布前换成正式美术 |
| 版本号 | `descriptor.mod` 与根部 `empire_validity_bypass.mod` 两处一致 | ✅ 1.2.0 |

上传步骤：

0. 先跑构建脚本，把「只该上传的东西」提取到 `build/empire_validity_bypass/`：

   ```powershell
   .\tools\build.bat          # Windows（启动器会调 tools\build.ps1）
   ```

   ```bash
   bash tools/build.sh        # Linux / macOS / Git Bash（chmod +x 后也可直接 ./tools/build.sh）
   ```

   两个脚本规则一致：先清空 `build/empire_validity_bypass/` 再重建，只放
   `descriptor.mod`、`thumbnail.png`、`README.txt` 和游戏内容目录；`.git/`、`tools/`、
   `dist/`、根目录 `empire_validity_bypass.mod`、`Thumbs.db` / `*.swp` / `*.log` /
   `*.psd` 之类一律不进去。构建完会打印文件清单、大小，并做校验（缺文件、
   `descriptor.mod` 里混进 `path=`、有被排除的文件残留都会直接报错退出）。
   同时会在 `build/workshop_build_item.vdf` 渲染好 steamcmd 上传参数。

   常用参数：`-h` 看帮助，`-n` 只演练（产物写临时目录、不碰 `build/`），
   `-o DIR` 换输出根目录，`--no-vdf` 跳过 VDF，`--workshop-id ID` 临时指定物品 ID。
   `-o` 指向源码目录或仓库根的上级会被拒绝——脚本要清空目标目录，护栏是必须的。

1. 完全退出游戏（启动器保持运行）。
2. 启动器 → `Mods` → 选中本地安装的 **虚境铸造：游牧兼容** → `Upload Mod`。
3. 登录 Paradox 账号（需与 Steam 关联），填标题、简介、版本、tags，上传。
4. 上传完成会得到 `PublishedFileId`：把它填到本 README 顶部那行链接里，并写进 CHANGELOG。

上传时把 `build/empire_validity_bypass/` 当作内容目录（steamcmd 的 `contentfolder`）；
用启动器上传的话，确认本地安装的那份与 `build/` 内容一致即可。

### 用 steamcmd 发布（可选，可脚本化）

`build` 脚本顺手会渲染 `build/workshop_build_item.vdf`（和内容目录同级，不会被上传）：

| 字段 | 来源 |
| --- | --- |
| `appid` | `publish.json` 的 `appId`，缺省 281990 |
| `contentfolder` / `previewfile` | 绝对路径，指向 `build/empire_validity_bypass/` 与其中的预览图 |
| `title` | `publish.json` 的 `title`，为空时用 `descriptor.mod` 的 `name` |
| `description` | `tools/workshop/description.bbcode`；`{{VERSION}}` / `{{SUPPORTED_VERSION}}` 会被替换，换行转义成 `\n` |
| `changenote` | `CHANGELOG.md` 里 `## <版本>` 那一节的条目（`publish.json` 有 `changenote` 就用它） |
| `visibility` | `publish.json` 的 `public` / `friends` / `private` / `unlisted` → `0` / `1` / `2` / `3` |
| `publishedfileid` | `tools/workshop/publishedfileid.txt`（纯数字），没有就是 `0` = 首次上传 |

```bash
steamcmd +login <账号> +workshop_build_item "<仓库>/build/workshop_build_item.vdf" +quit
```

首次上传后 steamcmd 会打印物品 ID，把它写进 `tools/workshop/publishedfileid.txt`，
之后每次更新都指向同一个物品（不写就会**每次新建一个重复物品**）。临时改一次用
`--workshop-id <ID>`；不想生成 VDF 就加 `--no-vdf`。

steamcmd 这条路径不吃 `descriptor.mod` 里的 `tags`，第一次上传后到物品页手动勾一次即可。
`build/` 和 `*.vdf` 都在 `.gitignore` 里，VDF 不会被提交。

上传之后：

- 启动器会给本地 `.mod` 补上 `remote_file_id="<PublishedFileId>"`，文件内容变化是正常的。
- 工坊目录里是 `empire_validity_bypass/` 的完整副本（含 `descriptor.mod`、`thumbnail.png`）。
- 更新流程：改版本号（两处）→ 重跑 `build` 脚本 → 再执行一次 `Upload Mod`，Steam 自动推送。
- 建议先设成「不公开 / Unlisted」自测一轮（订阅、开局、多人），确认没问题再改成公开。

不要上传的东西：`.git/`、`tools/`、`dist/`、`CHANGELOG.md`。
我们的结构把这些留在仓库根，mod 文件夹里只有游戏内容。有些工坊 mod 的目录里甚至带着
`.git/`，那是直接把仓库文件夹传上去的结果——`build` 脚本就是为了避免这种事。

## 工具脚本

| 脚本 | 用途 |
| --- | --- |
| `tools/install.ps1` | 本地安装：复制到用户数据目录、旧副本改名备份、`-Enable` 写 `dlc_load.json`、`-GameDataPath` 指定非默认目录 |
| `tools/package.ps1` | 打包 `dist/empire_validity_bypass-v<版本>.zip`（非工坊分发用），校验包内清单并输出 SHA256 |
| `tools/build.bat` | 纯 ASCII 启动器：挑 `pwsh` / `powershell` 并把参数原样转给 `build.ps1` |
| `tools/build.ps1` | Windows 侧实现：提取上传集合到 `build\empire_validity_bypass\`、渲染 `build\workshop_build_item.vdf`、清空重建、剔除无关文件、转义 VDF、校验后打印清单 |
| `tools/build.sh` | 同上，Linux / macOS / Git Bash 用；规则与 `build.ps1` 一致，VDF 逐字节相同（只有绝对路径是各自平台的写法） |
| `tools/common.ps1` | 路径探测（Steam 库 / Paradox 用户数据目录）等公共函数 |

`package.ps1` 出的 zip 是给「不想用 Steam 订阅」或自测的人用的：结构是 `mod/<id>.mod` +
`mod/<id>/...`，解压到 `Documents/Paradox Interactive/Stellaris` 即可。工坊玩家用不到它。

## 已知限制

- 只放行「游牧 + 虚境铸造」这一条组合，其它起源限制照旧生效。
- 判定在房主端执行：联机时房主也要启用本 mod，否则该设计仍可能被拒绝。
- 游戏小版本更新后原版定义可能变化，需要重新对照 `00_origins.txt` 补齐字段。
- 覆盖定义必须跟原版保持同步，否则会静默丢失原版新增或修改的字段。

## 开发约定

- Paradox 脚本：UTF-8 无 BOM、LF、Tab 缩进，与原版一致。
- `tools/*.ps1`：UTF-8 **带 BOM**（Windows PowerShell 5.1 读无 BOM 文件会把中文当 ANSI，
  导致解析报错）。编辑后确认前三个字节是 `EF BB BF`。
- `tools/*.sh`：UTF-8 **无 BOM + LF**（CRLF 会让 bash 报 `$'\r': command not found`）。
- `tools/build.bat`：**必须是纯 ASCII + CRLF**，逻辑一行都不要写进去。cmd 按字节读批处理并用
  当前代码页解码，中文跨过读缓冲边界时解析会错位，`rem` 行的后半截会被当成命令执行
  （`'<片段>' is not recognized as an internal or external command`）。所以它在
  `chcp`/UTF-8 上什么花活都不做，只负责转调 `tools/build.ps1`。
- `tools/*.ps1`：UTF-8 **带 BOM**（见上一条），CRLF。
- 换行约定写在 `.gitattributes`：`*.sh` 强制 LF，`*.bat` / `*.ps1` 强制 CRLF。
- Paradox 脚本在 `.gitattributes` 里标记为 `-text`，git 不做换行转换；`*.png` 标记为 `binary`。
- 版本号写在 `empire_validity_bypass.mod` 与 `empire_validity_bypass/descriptor.mod` 两处，
  必须同步；`package.ps1` 从 `descriptor.mod` 读取版本号。
- 换预览图：替换 `empire_validity_bypass/thumbnail.png`（保持文件名与 512×512 尺寸），
  `descriptor.mod` 里的 `picture` 字段不用改。

## 报告问题

附上 `Documents/Paradox Interactive/Stellaris/logs` 下的 `game.log` 与 `error.log`，
以及 mod 版本号与游戏版本号。

## 许可

[MIT](LICENSE) —— 可自由使用、修改、再分发。

---

Stellaris 是 Paradox Interactive 的商标。本仓库是非官方玩家 mod；其中的覆盖脚本是游戏
原始数据文件的修改副本，需要正版游戏才能使用。
