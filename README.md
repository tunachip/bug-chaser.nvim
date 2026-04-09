# bug-chaser.nvim

`bug-chaser.nvim` runs the current buffer or a selected range inside a dedicated terminal at the bottom of Neovim, parses the resulting stacktrace or compiler error, opens the failing source location, jumps to the reported line, and adds a virtual-line explanation directly in the buffer.

## Status

This is the initial implementation. It supports Python, Lua, JavaScript, TypeScript, C, C++, Go, Rust, and Zig with per-language runner configuration.

## Requirements

- Neovim 0.10+ for `vim.system`
- A matching runtime/compiler installed for the language you want to execute

Default runners:

- `python3`
- `lua`
- `node`
- `tsx`
- `cc`
- `c++`
- `go`
- `rustc`
- `zig`

## Setup

```lua
require("bug_chaser").setup({
  open_command = "split",
  terminal = {
    height = 12,
    focus = false,
  },
  virtual_line = {
    prefix = " ",
  },
  languages = {
    typescript = {
      command = { "bun", "run" },
      args = { "$file" },
      mode = "command",
    },
    cpp = {
      compiler = "clang++",
      compile_args = { "-std=c++23", "-g", "$file", "-o", "$target" },
      mode = "compiled",
      run_command = "$target",
      run_args = {},
    },
  },
})
```

## Usage

Run the entire buffer:

```vim
:BugChaserRun
```

Run only a selected section:

```vim
:'<,'>BugChaserRun
```

When the buffer is modified or a range is used, bug-chaser writes an isolated temporary source file, runs that file in the dedicated terminal, then remaps parsed stack frames back to the original buffer and line numbers.

## Configuration

Runner modes:

- `mode = "command"` uses `command` and `args`
- `mode = "compiled"` uses `compiler`, `compile_args`, `run_command`, and `run_args`

Available placeholders in runner arguments:

- `$file`
- `$target`
- `$cwd`
- `$source_dir`
- `$source_name`
- `$selection_start`
- `$selection_end`

Global options:

- `cwd = "buffer_dir" | "source_dir" | "cwd" | "/custom/path"`
- `open_command = "split"` by default
- `notify_on_success = false`
- `terminal = { height, focus, position, name }`
- `virtual_line = { prefix, highlight, above }`

Language keys:

- `python`
- `lua`
- `javascript`
- `typescript`
- `c`
- `cpp`
- `go`
- `rust`
- `zig`
