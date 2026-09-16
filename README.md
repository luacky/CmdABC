# CmdABC

CmdABC 是面向 Shell 的层级命令成员补全工具。它把 `/namespace.` 映射为可逐层选择的命令树，并在选中叶子后只把真实命令回填到当前 Shell 编辑行。

> 安全不变量：CmdABC 永远不自动执行选中的命令。

`C00｜需求冻结与核心交互可行性验证` 已关闭。核心 tree-picker UX 已在 macOS、ImmortalWrt、OCI Ubuntu 与 GCP Ubuntu 验收通过并冻结；本仓库目前只包含冻结规格和隔离原型，不包含同步、更新、安装/卸载、GUI 或生产部署。

## 仓库结构

- `docs/C00-SPEC.md`：C00 冻结规格、范围与验收标准。
- `docs/C00-FEASIBILITY.md`：Bash Readline / Zsh ZLE 的最小接管方案和已知边界。
- `docs/C00-RESULTS.md`：C00 最终自动化与三台 Linux 实机验收证据。
- `prototype/cmdabc`：只读取词库的层级 picker 原型。
- `prototype/shell/`：必须在隔离交互 Shell 中手动 `source` 的 Bash/Zsh 接入脚本。
- `prototype/command-library.txt`：C00 固定验收词库。
- `prototype/tests/`：静态测试与交互验收脚本。

## 安全试用

不要把 C00 原型写入 `~/.bashrc` 或 `~/.zshrc`。Bash 隔离试用必须分两步：先执行并等待新 prompt：

```sh
bash --noprofile --norc
```

然后再单独执行，不能把两条命令一次性粘贴：

```sh
source /absolute/path/to/prototype/shell/cmdabc.bash
```

Zsh 5.9 同样在隔离子 Shell 中 source：

```sh
zsh -f
source /absolute/path/to/prototype/shell/cmdabc.zsh
```

然后逐字输入 `/test.`。普通 `.` 保持原本的自插入行为；只有整行为 `/namespace.`、光标在行尾且实际键入最后一个 `.` 时才进入 picker。整段粘贴 `/test.` 后再按 Enter 不保证触发，这是 C00 已知行为。

```sh
./prototype/tests/static.sh
./prototype/tests/interactive-macos.sh
```

`interactive-macos.sh` 会在隔离子 Shell 中验证本机 zsh 5.9。Bash 部分只接受 5.2.x：可用 `CMDABC_BASH52_BIN=/path/to/bash-5.2` 显式指定，或让脚本检查 Homebrew 常见路径。macOS 自带 Bash 3.2 不在目标范围，不能替代 Bash 5.2 验收。
