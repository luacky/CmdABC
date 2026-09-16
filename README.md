# CmdABC

CmdABC 是面向 Shell 的层级命令成员补全工具。它把 `/namespace.` 映射为可逐层选择的命令树，并在选中叶子后只把真实命令回填到当前 Shell 编辑行。

> 安全不变量：CmdABC 永远不自动执行选中的命令。

`C00｜需求冻结与核心交互可行性验证` 已关闭。核心 tree-picker UX 已在 macOS、ImmortalWrt、OCI Ubuntu 与 GCP Ubuntu 验收通过并冻结。C01 正在建立 0.1.0 本地安装、卸载与发布包基线；同步、更新、GUI 和生产部署仍不在当前范围内。

## 仓库结构

- `docs/C00-SPEC.md`：C00 冻结规格、范围与验收标准。
- `docs/C00-FEASIBILITY.md`：Bash Readline / Zsh ZLE 的最小接管方案和已知边界。
- `docs/C00-RESULTS.md`：C00 最终自动化与三台 Linux 实机验收证据。
- `prototype/cmdabc`：只读取词库的层级 picker runtime；C01 installer 会复制它。
- `prototype/shell/`：Bash/zsh 接入脚本；C00 手动试用仍只在隔离交互 Shell 中 source。
- `prototype/command-library.txt`：C00 固定验收词库。
- `prototype/tests/`：静态测试与交互验收脚本。
- `install.sh`：将 0.1.0 程序安装到 `~/.cmdabc`，并注册当前 Bash/zsh。
- `uninstall.sh`：只撤销精确 managed block 并删除程序目录。
- `tests/install-uninstall.sh`：使用隔离临时 HOME 验证安装、重装、卸载和数据保护。

## C01 本地安装边界

程序安装在 `~/.cmdabc`，用户命令数据固定保存在 `~/.cmdabc-data/command-library.txt`。安装和重装只在词库不存在时创建空文件；已有词库不会被覆盖。普通卸载始终保留整个 `~/.cmdabc-data`。

`install.sh` 默认根据 `$SHELL` 注册 Bash 或 zsh，也可以通过 `CMDABC_SHELL=bash` 或 `CMDABC_SHELL=zsh` 明确选择。安装只维护对应 rc 中以下精确区块，不修改其他内容：

```sh
# >>> CmdABC >>>
source "$HOME/.cmdabc/shell/cmdabc.zsh"
# <<< CmdABC <<<
```

安装完成后需新开 Shell 生效。macOS Bash 仍只处理 `~/.bashrc`，不会修改 `.bash_profile` 或 `.profile`。

## 本地命令管理

`abc` 是 CmdABC 永久保留的系统 namespace，不写入用户词库，也不能被用户记录覆盖。输入 `/abc.` 可在 picker 中选择以下管理命令；选择只回填，随后按 Enter 才由 CmdABC 处理：

```text
/abc.list
/abc.add.<target> <command>
/abc.update.<target> <command>
/abc.del.<target>
/abc.help
```

例如 `/abc.add.git.status git status` 会把 `git.status git status` 写入用户词库，但不会执行 `git status`。新增、更新和删除均先写同目录临时文件，完整验证后再原子替换原词库。

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
