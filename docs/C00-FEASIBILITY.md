# C00｜Bash Readline 与 Zsh ZLE 可行性

## 结论

两个目标 Shell 都提供了不经过命令执行器、直接读写当前编辑缓冲区的入口，因此 CmdABC 的核心安全语义可实现。

- Bash：用 Readline `bind -x` 把 `.` 绑定到 shell function。function 先完成普通的 `.` 插入，然后检查 `READLINE_LINE` 和 `READLINE_POINT`。选中叶子时只赋值 `READLINE_LINE` / `READLINE_POINT`。
- Zsh：用 `zle -N` 定义 widget，用 `bindkey` 绑定 `.`。widget 先调用 ZLE 内建 `.self-insert`，然后检查 `BUFFER` 和 `CURSOR`。选中叶子时只赋值 `BUFFER` / `CURSOR`。

这条路径不需要伪造键盘输入，不向 Shell 推送换行，也不需要 `eval`。

## Bash 最小接管

GNU Bash 官方手册明确说明，`bind -x` 触发 shell command 时会设置 `READLINE_LINE`、`READLINE_POINT` 和 `READLINE_MARK`；如果回调修改这些值，新值会反映回编辑状态。

C00 widget 顺序：

```text
用户按 .
  → 在光标位置插入普通 .
  → 整行不匹配 ^/[A-Za-z0-9_-]+\.$ ：立即返回
  → 整行匹配且光标在行尾：运行 picker
      → 取消：保留 /namespace.
      → 选中叶子：READLINE_LINE=command
                         READLINE_POINT=command 长度
```

### 风险与 C00 边界

- 绑定 `.` 会覆盖当前 Readline keymap 中该键的原绑定。C00 只允许在 `bash --noprofile --norc` 隔离子 Shell 中 source，不写入用户配置。完整安装器必须在后续阶段设计可恢复的标记区块和绑定冲突策略。
- `READLINE_POINT` 按字节定位，C00 触发 namespace 限定为 ASCII 短名；command 回填后光标放在缓冲区末尾。
- 本机 macOS 自带 Bash 是 3.2.57，不在 v0.1 目标范围，也不能代替要求中的 Bash 5.2.21/5.2.37 验收。
- 隔离验收必须先单独执行 `bash --noprofile --norc`，等待新 prompt 出现，再单独 source 接入脚本；不能把两条命令一次性粘贴执行。
- widget 由用户实际键入最后一个 `.` 触发。整段粘贴 `/namespace.` 后再按 Enter 不保证触发，C00 不扩展 paste-trigger。

## Zsh 最小接管

Zsh 官方手册将 ZLE 操作抽象为 widgets。用户定义 widget 可读写特殊参数 `BUFFER` 和 `CURSOR`；`zle -N` 注册 widget，`bindkey` 将按键与它关联。

C00 widget 与 Bash 保持同一语义：先执行内建 `.self-insert`，只在整行精确匹配时启动 picker，最后只改写编辑缓冲区。C00 同样只允许在 `zsh -f` 隔离子 Shell 中 source。

## Picker 进程边界

picker 从 `/dev/tty` 读键、向 `/dev/tty` 绘制，只把最终选中的 command 写到 stdout。Shell widget 用 command substitution 接收这个字符串，但不执行它。

picker 的可见列表由根节点和当前已进入分支动态构建。父节点使用 `▸` / `▾` 表示折叠/展开，子项按层级缩进；未进入的同级分支不会递归构建到可见列表中。选择状态按完整 path 保存，使展开、折叠后仍能精确回到目标节点。

```text
Shell 编辑缓冲区
      │ /test.
      ▼
Shell widget ──启动──> cmdabc pick ──只读──> UTF-8 TXT
      ▲                         │
      │ stdout: echo TWO       │ /dev/tty: UI/按键
      └──只赋值缓冲区<────────────────┘
```

picker 取消时不向 stdout 输出 command。它使用 Bash builtin `read -r -s -n 1` 从 `/dev/tty` 读取主按键，并用 builtin `read -t` 区分 standalone Esc 与方向键后续字节，不依赖外部 `stty`。正常退出、错误、`INT` 或 `TERM` 时恢复光标并退出 alternate screen；每次 builtin `read` 自己恢复其临时终端读取状态。

ImmortalWrt 实机确认系统没有 `stty`，BusyBox 也没有对应 applet；上述 builtin-only 方案已在 ImmortalWrt、OCI Ubuntu 与 GCP Ubuntu 验收通过。

## 发布包边界

C00 的 macOS 验收 tar 包在 Ubuntu 解包时会出现 `LIBARCHIVE.xattr.com.apple.provenance` warning，但不影响校验和运行。正式发布流程必须清理 macOS 扩展属性并验证跨平台无警告解包；C00 不临时实现发布打包器。

## C00 非目标

原型不解决安装时的绑定冲突、主题/屏幕阅读器、超大词库索引、同步并发、上传、更新、秘密扫描或完整终端兼容矩阵。

## 官方参考

- [GNU Bash Reference Manual: Bash Builtins (`bind -x`)](https://www.gnu.org/software/bash/manual/html_node/Bash-Builtins.html)
- [GNU Bash Reference Manual: Command Line Editing](https://www.gnu.org/software/bash/manual/html_node/Command-Line-Editing.html)
- [Zsh Manual: Zsh Line Editor](https://zsh.sourceforge.io/Doc/Release/Zsh-Line-Editor.html)
