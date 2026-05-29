# bug-chaser.nvim

`bug-chaser.nvim` runs the current buffer or a selected range inside a dedicated terminal at the bottom of Neovim, parses the resulting stacktrace or compiler error, opens the failing source location, jumps to the reported line, and adds a virtual-line explanation directly in the buffer.

It can also own diagnostic virtual lines for LSP/compiler diagnostics, replacing Neovim's default virtual text with wrapped full-width virtual lines.

## Status

This is the initial implementation.
It supports many popular languages out of the box, including Python, Lua, JavaScript/TypeScript, shell scripts, C/C++, Go, Rust, Zig, Java, Kotlin, Scala, C#/.NET, PHP, Ruby, Perl, R, Julia, Swift, Dart, Elixir, Erlang, Clojure, Haskell, OCaml, F#, and VB, with per-language runner configuration.

## Requirements

- Neovim 0.10+ for `vim.system`
- A matching runtime/compiler installed for the language you want to execute

Default runners use the standard CLI/runtime for each language when available, such as:

- `python3`, `lua`, `node`, `tsx`
- `bash`, `zsh`, `fish`, `pwsh`
- `cc`, `c++`, `go`, `cargo`, `rustc`, `zig`
- `java`, `kotlinc`, `scala`, `dotnet`, `dotnet-script`
- `php`, `ruby`, `perl`, `Rscript`, `julia`, `swift`, `dart`
- `elixir`, `escript`, `clojure`, `runghc`, `ocaml`, `vbnc`

## Setup

```lua
require("bug_chaser").setup({
  diagnostics = {
    virtual_lines = {
      enabled = true,
    },
  },
  open_command = "split",
  terminal = {
    height = 0.25,
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
    python = {
      commands = {
        ["all-tests"] = {
          command = "pytest",
          args = { "-q" },
          capture = "none",
          mode = "command",
        },
        ["current-buffer"] = {
          command = "python3",
          args = { "$file" },
          mode = "command",
        },
      },
    },
    rust = {
      commands = {
        ["cargo-run"] = {
          command = "cargo",
          args = { "run" },
          capture = "none",
          mode = "command",
        },
        ["current-buffer"] = {
          compiler = "rustc",
          compile_args = { "--crate-name", "bug_chaser", "$file", "-g", "-o", "$target" },
          mode = "compiled",
          run_command = "$target",
          run_args = {},
        },
      },
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

Run a named command directly:

```vim
:Run all-tests
```

When a language exposes multiple named commands, `:Run` and `:BugChaserRun` will prompt you to choose one. If a language only has a single command, bug-chaser runs it immediately.

Commands that capture the current buffer keep the existing behavior: when the buffer is modified or a range is used, bug-chaser writes an isolated temporary source file, runs that file in the dedicated terminal, then remaps parsed stack frames back to the original buffer and line numbers.

## Configuration

Runner modes:

- `mode = "command"` uses `command` and `args`
- `mode = "compiled"` uses `compiler`, `compile_args`, `run_command`, and `run_args`

Language commands:

- `commands = { ["name"] = { ... } }` defines multiple named run choices for a language
- `capture = "buffer"` keeps the current buffer/range execution flow
- `capture = "none"` runs a named script or project command without creating a temp source file

Available placeholders in runner arguments:

- `$file`
- `$target`
- `$cwd`
- `$source_dir`
- `$source_name`
- `$selection_start`
- `$selection_end`

Global options:

- `diagnostics = { virtual_lines = { enabled, source, severity, trailing_pad } }`
- `cwd = "buffer_dir" | "source_dir" | "cwd" | "/custom/path"`
- `open_command = "split"` by default
- `notify_on_success = false`
- `terminal = { height, focus, position, name }`
  `height` accepts either a fixed line count such as `12` or a fraction such as `0.25` for 25% of the full Neovim height
- `virtual_line = { prefix, highlight, above }`

Commands:

- `:BugChaserRun`
- `:BugChaserRun {name}`
- `:Run`
- `:Run {name}`
- `:BugChaserToggleDiagnosticVirtualLines`

Language keys include:

- `python`, `lua`, `javascript`, `javascriptreact`, `typescript`, `typescriptreact`
- `sh`, `bash`, `zsh`, `fish`, `powershell`
- `c`, `cpp`, `go`, `rust`, `zig`
- `java`, `kotlin`, `scala`, `csharp`, `fsharp`, `vb`
- `php`, `ruby`, `perl`, `r`, `julia`, `swift`, `dart`
- `elixir`, `erlang`, `clojure`, `haskell`, `ocaml`
