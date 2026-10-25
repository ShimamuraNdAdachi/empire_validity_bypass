虚境铸造：游牧兼容 (empire_validity_bypass) 1.2.0
=================================================

只改一条规则：origin_shroud_forged 的 possible 里去掉 is_nomadic = no，
让「游牧 + 虚境铸造」的帝国设计通过起源合法性校验。

需要 Shadows of the Shroud DLC。
以下原版限制保留：
  - 必须是智械权威 auth_machine_intelligence
  - 不能是 civic_machine_servitor / terminator / assimilator / chosen

覆盖方式：common/governments/civics 是 LIOS（后加载覆盖先加载），
文件名 zzz_ 前缀保证排在原版 00_origins.txt 之后。

来源与变更记录见仓库根目录 README.md / CHANGELOG.md。
