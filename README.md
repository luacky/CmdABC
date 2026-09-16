# CmdABC

**Make shell commands as easy as ABC.**

English | [简体中文](README.zh-CN.md)

CmdABC is a lightweight hierarchical command manager and picker for the shell.

Type `/namespace.` to open a command tree. After you select a leaf command, CmdABC inserts it into the current command line — **it never executes the command automatically**.

## Supported environments

CmdABC 0.1.0 supports:

- macOS with zsh 5.9
- Bash 5.2 target environments, including macOS, Ubuntu, and ImmortalWrt

## Installation

Extract the release package, then run:
```sh
./install.sh
```

No administrator privileges are required.

Open a new shell after installation for the configuration to take effect.

CmdABC program files are installed to:
```text
~/.cmdabc
```

Your command library is stored separately at:
```text
~/.cmdabc-data/command-library.txt
```

If the command library already exists, installation and reinstallation leave it untouched.

## Command picker

Type a namespace followed by a final dot:
```text
/namespace.
```

CmdABC opens the matching command tree in place.

Keyboard controls:

- `↑` / `↓` — move through visible items
- `→` / `Enter` — expand a parent or select a leaf
- `←` — return to the parent and collapse
- `Esc` — cancel

Selecting a leaf only fills the current shell command line. CmdABC does not execute it for you.

## Managing commands

CmdABC includes a built-in `/abc.*` management namespace.

Available commands:
```text
/abc.help
/abc.list
/abc.add.<target> <command>
/abc.update.<target> <command>
/abc.del.<target>
```

The `abc` and `abc.*` namespaces are reserved for CmdABC itself and cannot be used for user commands.

Commands added or updated through `/abc.*` are stored as data only. They are not executed automatically.

## Uninstallation

Run:
```sh
~/.cmdabc/uninstall.sh
```

Uninstallation removes CmdABC program files and its managed shell configuration.

Your command library is preserved:
```text
~/.cmdabc-data/command-library.txt
```

Reinstalling CmdABC will continue to use the existing command library.

## Data safety

CmdABC keeps program files and user data separate:
```text
~/.cmdabc/        # program files
~/.cmdabc-data/   # user data
```

Normal installation, reinstallation, and uninstallation do not overwrite or delete an existing user command library.

CmdABC also never automatically executes a command selected from the picker.

## Version

Current release:
```text
0.1.0
```
