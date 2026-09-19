# CmdABC

**敲命令，简单如 ABC。**

[English](README.md) | 简体中文

CmdABC 是面向 Bash 和 zsh 的轻量级层级命令选择与管理工具。

输入 namespace，并手动敲下最后一个 `.` 即可打开命令树。选择叶子后，CmdABC 只把命令回填到当前 Shell 编辑行，不会自动执行。

## 截图

### 命令选择

![CmdABC 命令选择](docs/images/cmdabc-01-command-tree.png)

### 内置管理

![CmdABC 内置管理](docs/images/cmdabc-02-management.png)

### 只回填，不执行

![CmdABC 命令回填](docs/images/cmdabc-03-command-fill.png)

### 单条错误不影响其他命令

![CmdABC 容错提示](docs/images/cmdabc-04-invalid-entry.png)

叶子节点会显示灰色命令预览。单条格式错误不会拖累整个命令库；能够识别的异常叶子显示为 `???`，只有选中时才提示具体错误。

## 安装

解压发布包后运行：

```sh
./install.sh
```

无需管理员权限。

安装后新开一个 Shell 即可使用。已经打开的 Shell 会保留旧的 CmdABC 函数；安装器也会提示如何在当前 Shell 中重新载入。

程序文件：

```text
~/.cmdabc/
```

用户命令库：

```text
~/.cmdabc-data/command-library.txt
```

安装和重新安装都不会覆盖已经存在的命令库。

## 命令选择

输入 namespace，然后手动敲下最后一个点：

```text
/namespace.
```

> 整段粘贴 `/namespace.` 不会触发 picker，最后一个 `.` 必须手动输入。

操作：

- `↑` / `↓` — 移动选择
- `→` / `Enter` — 展开父节点或选择叶子
- `←` — 返回父节点并折叠
- `Esc` — 取消

## 管理命令

CmdABC 保留 `/abc.*` namespace 用于内置管理：

```text
/abc.help
/abc.list
/abc.add.<target> <command>
/abc.update.<target> <command>
/abc.del.<target>
```

即使命令库中存在个别格式错误，`/abc.list` 仍会列出其他正常记录；写操作继续保持严格校验，避免意外重写损坏的数据。

## 卸载

运行：

```sh
~/.cmdabc/uninstall.sh
```

CmdABC 会删除程序文件和它管理的 Shell 配置，同时保留：

```text
~/.cmdabc-data/
```

以后重新安装会继续使用原来的命令库。

## 已测试环境

- macOS — zsh 5.9
- macOS — GNU Bash 5.2
- Ubuntu — Bash 5.2
- ImmortalWrt — Bash 5.2

### macOS Bash 说明

安装器只维护 `~/.bashrc`，不会修改 `~/.bash_profile` 或 `~/.profile`。如果 Bash 以 login shell 启动，需要由现有配置负责加载 `~/.bashrc`。

## License

[MIT](LICENSE)
