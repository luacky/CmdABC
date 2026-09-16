# CmdABC

[English](README.md) | 简体中文

CmdABC 是面向 Shell 的层级命令管理与选择工具。输入 `/namespace.` 可以打开命令树；选择叶子后，CmdABC 只把命令回填到当前编辑行，不会自动执行。

CmdABC 0.1.0 支持：

- macOS zsh 5.9
- Bash 5.2 目标环境，包括 macOS、Ubuntu 和 ImmortalWrt

## 安装

解压发布包后，在包目录中运行：

```sh
./install.sh
```

安装不需要管理员权限。完成后新开一个 Shell 使配置生效。

程序安装在 `~/.cmdabc`。用户命令数据单独保存在：

```text
~/.cmdabc-data/command-library.txt
```

安装或重新安装不会覆盖已经存在的用户数据。

## 管理命令

`abc` 是 CmdABC 保留的系统 namespace。可使用：

```text
/abc.help
/abc.list
/abc.add.<target> <command>
/abc.update.<target> <command>
/abc.del.<target>
```

例如：

```text
/abc.add.git.status git status
/abc.update.git.status git status --short
/abc.del.git.status
```

新增或更新只保存 command 文本，不会执行它。

## 使用 picker

逐字输入 `/namespace.` 会打开该 namespace 的命令树：

- `↑ / ↓`：移动选择
- `Enter / →`：展开父节点或选择叶子
- `←`：返回父节点并折叠
- `Esc`：取消

选择叶子只回填命令。确认当前编辑行内容后，由用户自行按 Enter 执行。

## 卸载

运行：

```sh
~/.cmdabc/uninstall.sh
```

普通卸载会删除程序和 CmdABC 管理的 shell rc 区块，但保留整个 `~/.cmdabc-data` 以及其中的用户命令。以后重新安装会继续使用这些数据。

## macOS Bash 边界

Bash installer 只维护 `~/.bashrc`，不会自动修改 `~/.bash_profile` 或 `~/.profile`。如果 macOS Bash 以 login shell 启动，需要由用户现有配置负责加载 `~/.bashrc`。
