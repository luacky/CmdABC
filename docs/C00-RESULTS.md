# C00｜最终验证记录

日期：2026-09-16
状态：**CLOSED**
结论：**核心交互、stty-free 输入与 tree picker 已在全部目标环境 PASS。**

## 1. 收口边界

C00 只交付冻结规格、可行性结论、隔离原型和验收测试。未实现同步、更新、安装/卸载、GUI、生产部署或 C01 功能；未写入用户 Shell 配置。

本记录汇总本地自动化证据和三台目标实机的最终人工验收结果。C00 关闭后，核心 tree-picker UX 除修复真实 bug 外冻结。

## 2. 本地自动化

本地环境：Apple Silicon ARM64、macOS Darwin 27.0.0、zsh 5.9，以及只在 `/tmp` 编译且未安装到系统的 GNU Bash 5.2.37。

- GNU Bash 5.2.37 源码包 SHA-256：`9599b22ecd1d5787ad7d3b7bf0c59f312b3396d1e281175dd1f8a4014da621ff`。
- `prototype/tests/static.sh`：PASS。
- Bash 5.2.37 Shell 语法检查：PASS。
- zsh 5.9 Shell 语法检查：PASS。
- `prototype/tests/interactive-macos.sh`：Bash 5.2.37 与 zsh 5.9 PASS。
- standalone Esc、四方向键、Enter、叶子回填后编辑与不执行：PASS。
- 三层、多父分支 tree picker：PASS。
- 运行时 `PATH` 明确不含 `stty` 时，Bash、zsh 和三层树 PTY 回归：PASS。

静态守卫同时确认：

- 无 `eval`；
- picker 无外部 `stty` 依赖；
- 无旧的层级提示；
- 折叠/展开标记分别为 `▸` / `▾`。

## 3. 三台目标实机

| 环境 | 架构 | Shell | 结果 |
|---|---|---|---:|
| ImmortalWrt | Linux aarch64 | GNU Bash 5.2.37 | PASS |
| OCI Ubuntu | Linux x86_64 | GNU Bash 5.2.21 | PASS |
| GCP Ubuntu | Linux x86_64 | GNU Bash 5.2.21 | PASS |

三台均确认：

- 测试包 SHA-256、词库 validate 正常；
- `/test.` 精确触发，普通 `.` 不触发；
- standalone Esc、`↑`、`↓`、左方向键、右方向键正常；
- Enter 与右方向键语义一致；
- tree picker 原地按需展开正常；
- 父节点 `▸` / `▾`、叶子无箭头、每层两个空格缩进正常；
- 三层树正常；
- 只展开当前分支，切换父分支时旧分支自动折叠；
- 左方向键逐层返回并折叠；
- 叶子只回填、不自动执行，回填后仍可编辑；
- no-exec 副作用哨兵 PASS；
- Shell 配置前后哈希一致；
- 测试退出后父 Shell 正常。

最终实机包：`cmdabc-c00-immortalwrt-smoke-20260915-tree-picker.tar.gz`，SHA-256：

```text
6ecaec824e92fb3a1904dfb09019d2037b4d21fb082919d531bb7119d3f6ce45
```

该包是本地验收制品，不进入 baseline commit；仓库提交源文件、测试与可复现步骤。

## 4. C00 重要发现与冻结决策

### 4.1 ImmortalWrt 无 `stty`

ImmortalWrt 不提供 `stty`，BusyBox 也没有 `stty` applet。picker 已改为 Bash builtin `read -r -s -n 1` 读取主按键，并用 builtin `read -t` 读取 Esc 后续字节，完全移除外部 `stty` 依赖。

### 4.2 Tree picker UX 冻结

最终 UX 从逐级换页改为原地按需展开：父节点折叠为 `▸`、展开为 `▾`，叶子无箭头，每层缩进两个空格，只展开当前分支，切换父分支时旧分支自动折叠。该核心 UX 已通过三台实机验收并确认满意，后续除真实 bug 外冻结。

### 4.3 Bash 隔离测试必须分两步

必须先单独执行 `bash --noprofile --norc`，等待新 Bash prompt 出现，再单独执行 `source ./shell/cmdabc.bash`。不要把两条命令一次性粘贴执行。

### 4.4 触发依赖实际键入最后一个 `.`

当前 widget 依赖用户实际键入最后一个 `.`。整段粘贴 `/test.` 或 `/tree.` 后再按 Enter 不保证触发。C00 将其记录为已知行为，不临时扩展 paste-trigger 支持。

### 4.5 macOS tar 扩展属性警告

macOS 打出的 tar 包在 Ubuntu 解包时出现 `LIBARCHIVE.xattr.com.apple.provenance` warning。它不影响文件校验和运行，但正式发布包必须清理 macOS 扩展属性并验证跨平台无警告解包。

## 5. 最终结论

C00 的全部验收标准已满足，状态正式标记为 **CLOSED**。后续工作必须从单独的 C01 目标和门禁开始，不在本阶段追加功能。
