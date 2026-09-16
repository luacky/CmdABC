# C00｜需求冻结与核心交互可行性验证

状态：C00 CLOSED；核心 tree-picker UX 已冻结（2026-09-16）
项目名：CmdABC
可执行程序：`cmdabc`
CmdABC 自身 namespace：`/abc.`

## 1. 产品定位

CmdABC 是面向 Shell 的层级命令成员补全工具，不是普通 snippet 搜索器。它将 IDE/编程语言中 `object. → member → submember` 的逐层补全交互带到 Terminal。

例如：

```text
/codex.
> token
  log ▸
  usage

展开 log：
  token
  log ▾
  > view
    clear
  usage
```

选择 `view` 后，CmdABC 将真实命令回填到当前 Shell 输入行并退出。用户可继续编辑，只有用户之后再次按 Enter，命令才由 Bash/Zsh 执行。

**CmdABC 永远不自动执行选中命令。**

## 2. v0.1 目标环境

| 环境 | Shell | 架构 |
|---|---|---|
| macOS | zsh 5.9 | Apple Silicon ARM64 |
| ImmortalWrt | Bash 5.2.37 | ARM64 / aarch64 |
| OCI Ubuntu | Bash 5.2.21 | x86_64 |
| GCP Ubuntu | Bash 5.2.21 | x86_64 |

v0.1 不支持 WSL2、PowerShell、CMD、ash、fish 或 GUI。

## 3. CommandLibrary

长期 Source of Truth 必须是普通 UTF-8 TXT，一行一条：

```text
[path] [command]
```

示例：

```text
codex.token codex exec --ephemeral --ignore-user-config --ignore-rules --skip-git-repo-check --sandbox read-only --model gpt-5.6-luna "Reply with exactly OK."
codex.log.view tail -f ~/.codex/logs/codex.log
codex.log.clear rm -f ~/.codex/logs/codex.log
oci.login ssh -i ~/.ssh/example_key ubuntu@203.0.113.10
```

解析与结构规则：

1. 第一个空白以前全部属于 `path`。
2. 第一个空白以后全部原样属于真实 `command`。
3. `path` 用 `.` 表示层级，以短英文为主，且不允许空格。
4. 同一完整 `path` 不允许重复。
5. 一个节点不能同时是命令和父节点；例如 `codex.log <command>` 与 `codex.log.view <command>` 不能并存。
6. 空行忽略。
7. 以 `#` 开头的整行是备注。
8. v0.1 只处理单行 command，不处理 heredoc 或多行脚本。

C00 原型为了使层级可导航，将空 path segment（前导 `.`、尾随 `.` 或 `..`）视为无效输入。这是解析器结构约束，不改变上述数据模型。

## 4. 触发与层级交互

仅当当前输入行完整匹配 `/namespace.`，光标在行尾，且用户输入最后一个 `.` 时触发。`/c`、`/cod`、`/codex` 和普通 `.` 不触发。

触发依赖实际键入最后一个 `.`。整段粘贴 `/namespace.` 后再按 Enter 不保证触发；paste-trigger 支持不属于 C00。

进入 picker 后：

| 按键 | 行为 |
|---|---|
| `↑` / `↓` | 在当前可见节点之间循环移动选择 |
| `Enter` / `→` | 父节点：原地展开并进入第一个子项；叶子：回填命令并退出 |
| `←` | 当前在子项：回到父节点并折叠该分支；根层无动作 |
| `Esc` | 取消并保留原输入行 |

picker 使用按需展开的树形结构，不逐级换页。未展开父节点显示 `▸`，已展开父节点显示 `▾`，叶子不显示箭头；子节点在父节点下方缩进显示。任何时刻只展开用户当前进入的分支，不一次性展开整棵树，也不增加树线、图标、动画或复杂配色。

用户只手动输入第一个 `.`。进入 picker 后的层级移动不要求用户继续输入 `/codex.log.`。

## 5. 回填不变量

选中叶子后：

1. picker 完全退出；
2. 当前 Shell 编辑缓冲区替换为真实 command；
3. 光标放在 command 末尾；
4. Shell 回到正常编辑状态，允许移动、删除、改参数等；
5. CmdABC 不发送换行，不调用 `eval`，不调用 shell 执行 command。

## 6. 添加命令（已冻结，非 C00 实现项）

`Ctrl+T` 进入添加模式。用户输入 path 并粘贴真实 command，然后选择：

```text
[Enter] 添加并上传
[2]     仅添加到本机
[3]     取消
```

已存在 path 不允许静默覆盖。修改或重命名通过直接编辑 TXT 完成，不在 CLI 中完成。上传失败时本地记录不得丢失。

## 7. 同步与更新（已冻结，非 C00 实现项）

OCI 是唯一中央 Hub。同步通过 SSH，不引入 Web API、Web 后台、数据库服务、常驻 CmdABC daemon 或自动后台同步。

```text
cmdabc update  # 程序更新
cmdabc sync    # CommandLibrary 同步
```

两者必须分开且只能主动触发。具体同步协议留待后续阶段。

## 8. 安全规则

- CommandLibrary 不保存私钥正文、助记词、API Key、Cookie、Bearer Token 或密码。
- 可保存 SSH 私钥路径、IP、用户名和环境变量引用。
- 未来安装器只能操作 `~/.bashrc` / `~/.zshrc` 中 CmdABC 明确标记的区块。
- 卸载不能破坏用户其他 Shell 配置。

## 9. C00 范围

C00 只做：

- 建立仓库和文档结构；
- 固化本规格；
- 调研 Bash Readline 与 Zsh ZLE 最小接管方案；
- 以固定 `/test.` 词库验证层级选择和“只回填、不执行”。

C00 不做 OCI 同步、自动更新、完整 install/uninstall、GUI、完整 TUI 管理后台、WSL2、PowerShell、GitHub 发布或大规模 CommandLibrary 迁移。

## 10. C00 验收标准

1. Bash 5.2 能捕获 `/test.` 触发。
2. 普通 `.` 输入完全不受影响。
3. picker 以 `▸` / `▾` 原地按需显示树，不显示长 command 或旧层级提示。
4. 子节点在父节点下缩进，只展开当前进入的分支。
5. `↑` / `↓` 可在当前可见节点间选择。
6. `Enter` / `→` 可展开父节点并进入首个子项。
7. `←` 可返回父节点并折叠分支，根层无动作。
8. `Esc` 可取消。
9. 叶子 `Enter` / `→` 只回填 command，不执行。
10. 回填后恢复正常 Bash 编辑状态。
11. Zsh 5.9 完成同等原型与交互验收。
12. ImmortalWrt Bash 5.2.37、OCI Ubuntu Bash 5.2.21、GCP Ubuntu Bash 5.2.21 实机 PASS。
13. 不修改生产服务器，不部署 OCI，不破坏现有 Shell 配置。
