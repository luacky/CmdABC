# CmdABC

CmdABC 是面向 Bash 和 zsh 的轻量命令库与命令选择工具。装好后，只需记住 `/abc.`。

[English](README.md) | 简体中文

## 快速开始

解压发布包并运行：

```sh
./install.sh
```

打开新的 Shell，然后亲手输入最后一个 `.`：

```text
/abc.
```

![CmdABC 管理菜单：add、del、list](docs/images/cmdabc-02-management.png)

选择 `add`、`del` 或 `list`，接下来按照屏幕提示操作。

## 管理命令

`/abc.` 会打开管理菜单：

- `add` — 添加命令
- `del` — 删除命令
- `list` — 查看命令和错误

Add 界面会依次引导输入名称和命令：

![CmdABC Add 命令阶段](docs/images/cmdabc-05-add.png)

List 会一起显示已保存的命令和错误：

![CmdABC List 页面：正常记录与错误记录](docs/images/cmdabc-04-list.png)

## 使用已保存的命令

假设保存了名称 `git.status`，输入 `/git.` 即可打开命令树。最后一个 `.` 必须亲手输入；整段粘贴不会触发选择界面。

![CmdABC 命令树](docs/images/cmdabc-01-command-tree.png)

- `↑` / `↓` — 在可见项目间移动
- `→` / `Enter` — 展开分支或选择命令
- `←` — 返回并折叠分支
- `Esc` — 取消

选择命令后，CmdABC 只会将它填入当前 Shell 命令行，不会自动执行。

![命令回填到 Shell 编辑行](docs/images/cmdabc-03-command-fill.png)

## 用户数据

命令保存在 `~/.cmdabc-data/command-library.txt`。日常使用不需要编辑这个文件，进入 `/abc.` 即可。高级用户也可以直接编辑文件，批量管理命令。

安装、重新安装和卸载都会保留命令库。

### 手工文件格式

每条命令占一行，格式为 `name command`：

```text
git.status git status
docker.ps docker ps
```

在选择界面中，名称从 `/` 后开始，到第一个空格前结束。名称必须至少包含一个 `.`，例如 `a.b`。写入文件时不要带开头的 `/`。第一个空格后的完整 Shell 内容是命令。

首个非空白字符为 `#` 的整行是注释：

```text
# git.status git status
```

命令中的行内 `#` 仍属于命令内容：

```text
demo.echo echo hello # test
```

## 安全与兼容性

CmdABC 只回填选中的命令，不会自动执行。单条格式错误不会隐藏其他正常命令；重复名称会被判为无效。CmdABC 不使用 `eval` 或 `stty`。

已验证环境：macOS 上的 zsh 5.9 和 GNU Bash 5.2；Ubuntu、ImmortalWrt 上的 Bash 5.2。

## 安装与卸载

运行 `./install.sh` 无需管理员权限。程序文件安装在 `~/.cmdabc/`，安装器会提示如何让已打开的 Shell 重新载入；新开的 Shell 会自动载入。

卸载命令：

```sh
~/.cmdabc/uninstall.sh
```

安装器只管理 Bash 的 `~/.bashrc`，不会修改 `~/.bash_profile` 或 `~/.profile`。如果 Bash 以 login shell 启动，需要由现有配置载入 `~/.bashrc`。

## 许可证

[MIT](LICENSE)
