# C00｜Linux 实机 picker 重测步骤与结果

状态：**三台目标实机 PASS；C00 CLOSED。**

| 环境 | Shell | 结果 |
|---|---|---:|
| ImmortalWrt Linux aarch64 | GNU Bash 5.2.37 | PASS |
| OCI Ubuntu Linux x86_64 | GNU Bash 5.2.21 | PASS |
| GCP Ubuntu Linux x86_64 | GNU Bash 5.2.21 | PASS |

以下步骤保留为已完成验收的可复现记录。

## 1. 校验与解包

把以下两个文件复制到 ImmortalWrt 的同一临时目录：

- `cmdabc-c00-immortalwrt-smoke-20260915-tree-picker.tar.gz`
- `cmdabc-c00-immortalwrt-smoke-20260915-tree-picker.tar.gz.sha256`

在目标 Linux 主机上执行：

```sh
cd /tmp
sha256sum -c cmdabc-c00-immortalwrt-smoke-20260915-tree-picker.tar.gz.sha256
tar -xzf cmdabc-c00-immortalwrt-smoke-20260915-tree-picker.tar.gz
cd cmdabc-c00-immortalwrt-smoke-20260915-tree-picker
sha256sum -c SHA256SUMS
```

两次校验都必须 PASS。不要安装额外软件包，也不要把内容写入用户 Shell 配置。

## 2. 只读基线与非交互 smoke

```sh
uname -a
bash --version | sed -n '1p'
command -v stty || printf 'stty: NOT FOUND\n'
bash ./cmdabc validate --library ./command-library.txt
bash ./cmdabc validate --library ./tree-library.txt
bash ./cmdabc children --library ./command-library.txt --path test
bash ./cmdabc children --library ./command-library.txt --path test.group
```

预期关键结果：

```text
stty: NOT FOUND
OK: 3 command records
OK: 4 command records
one    leaf    echo ONE
group  parent
two    leaf    echo TWO
three  leaf    echo THREE
```

列之间实际为 Tab。任何 `stty` 缺失报错都算 FAIL。

## 3. Shell 配置前置哈希

```sh
for file in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile" "$HOME/.zshrc"; do
  [ ! -f "$file" ] || sha256sum "$file"
done > /tmp/cmdabc-shell-before.sha256
cat /tmp/cmdabc-shell-before.sha256
```

## 4. 固定词库交互矩阵

在包目录启动一次性隔离 Bash。先只执行：

```sh
bash --noprofile --norc
```

等待新 Bash prompt 出现后，再单独执行：

```sh
source ./shell/cmdabc.bash
```

不要把上述两条命令一次性粘贴执行。

逐项手动验证，回填后不要再按 Enter：

1. 输入 `echo ordinary.txt`，确认普通 `.` 不触发 picker，再用 `Ctrl-U` 清行。
2. 输入 `/test.`，确认显示 `one` 与 `group ▸`，叶子 `one` 无箭头，且不显示长 command。
3. 单独按一次 `Esc`，确认 picker 取消且原始 `/test.` 仍在；输入 `cancel` 后应得到 `/test.cancel`，再用 `Ctrl-U` 清行。
4. 再输入 `/test.`；验证 `↑`、`↓` 循环选择。
5. 选中 `group ▸` 后按 `→`：画面仍保持 `/test.` 根树，`group` 原地变为 `group ▾`，其下缩进显示 `two`、`three`，选择进入 `two`。
6. 在展开树内验证 `↑`、`↓` 会经过 `one`、`group`、`two`、`three` 等全部当前可见节点。
7. 在子项按 `←`：选择回到 `group`，子项消失，标记恢复为 `group ▸`；在根层按 `←` 应无动作。
8. 再对 `group ▸` 按 `Enter`，确认与右方向键等价；在 `two` 上按 `→` 或 `Enter`，picker 应退出，编辑行只出现 `echo TWO`，不得出现命令执行产生的独立 `TWO` 输出。
9. 用 `←` 移动光标并插入 `X`，确认回填行仍可编辑；随后按 `Ctrl-C` 丢弃，切勿执行。

第 3 项必须先等待 picker 完成取消再继续输入；第 4 至 8 项证明完整方向键 Escape Sequence 没有被误判为 standalone Esc。

## 5. 三层与按需展开

退出上一个隔离 Bash，仍在包目录先执行：

```sh
CMDABC_LIBRARY=./tree-library.txt bash --noprofile --norc
```

等待新 Bash prompt 出现后，再单独执行：

```sh
source ./shell/cmdabc.bash
```

输入 `/tree.` 后验证：

1. 初始只显示 `alpha ▸`、`beta ▸`、`gamma ▸`，不显示其子项。
2. 展开 `alpha` 后只出现缩进的 `leaf`；`beta`、`gamma` 保持折叠。
3. 从 `leaf` 用下方向键移动到 `beta` 并展开；`alpha` 应自动恢复为 `alpha ▸`，只在 `beta ▾` 下出现 `one` 和 `deep ▸`。
4. 进入 `deep ▸` 后变为 `deep ▾`，其下进一步缩进显示 `final`。
5. 从 `final` 连续按两次左键：先回到并折叠 `deep`，再回到并折叠 `beta`。
6. 按 `Ctrl-C` 退出当前输入，再退出隔离 Bash。

## 6. 叶子绝不执行的副作用证据

退出上一个隔离 Bash，仍在包目录先执行：

```sh
printf 'test.leaf touch /tmp/cmdabc-c00-must-not-exist\n' > /tmp/cmdabc-c00-noexec.txt
CMDABC_LIBRARY=/tmp/cmdabc-c00-noexec.txt bash --noprofile --norc
```

等待新 Bash prompt 出现后，再单独执行：

```sh
source ./shell/cmdabc.bash
```

输入 `/test.`，在唯一叶子 `leaf` 上按 `Enter`。编辑行应只回填：

```text
touch /tmp/cmdabc-c00-must-not-exist
```

不要按 Enter；按 `Ctrl-C` 丢弃回填行，然后执行：

```sh
[ ! -e /tmp/cmdabc-c00-must-not-exist ] && printf 'PASS: leaf filled but did not execute\n'
exit
```

## 7. Shell 配置后置哈希

```sh
for file in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile" "$HOME/.zshrc"; do
  [ ! -f "$file" ] || sha256sum "$file"
done > /tmp/cmdabc-shell-after.sha256
cmp /tmp/cmdabc-shell-before.sha256 /tmp/cmdabc-shell-after.sha256 \
  && printf 'PASS: shell configuration hashes unchanged\n'
```

以上项目已在三台目标实机全部 PASS。测试包从 macOS 解包到 Ubuntu 时出现 `LIBARCHIVE.xattr.com.apple.provenance` warning，不影响哈希和运行；正式发布包需清理该扩展属性。C00 状态为 **CLOSED**。
