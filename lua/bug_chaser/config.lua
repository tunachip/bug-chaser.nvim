local util = require("bug_chaser.util")

local M = {}

local defaults = {
  cwd = "buffer_dir",
  notify_on_success = false,
  open_command = "split",
  terminal = {
    focus = false,
    height = 12,
    name = "bug-chaser://runner",
    position = "botright",
  },
  virtual_line = {
    above = true,
    highlight = "DiagnosticVirtualTextError",
    prefix = " ",
  },
  languages = {
    python = {
      args = { "$file" },
      command = "python3",
      mode = "command",
    },
    lua = {
      args = { "$file" },
      command = "lua",
      mode = "command",
    },
    javascript = {
      args = { "$file" },
      command = "node",
      mode = "command",
    },
    typescript = {
      args = { "$file" },
      command = "tsx",
      mode = "command",
    },
    c = {
      compile_args = { "-g", "$file", "-o", "$target" },
      compiler = "cc",
      mode = "compiled",
      run_args = {},
      run_command = "$target",
    },
    cpp = {
      compile_args = { "-std=c++20", "-g", "$file", "-o", "$target" },
      compiler = "c++",
      mode = "compiled",
      run_args = {},
      run_command = "$target",
    },
    go = {
      compile_args = { "build", "-o", "$target", "$file" },
      compiler = "go",
      mode = "compiled",
      run_args = {},
      run_command = "$target",
    },
    rust = {
      compile_args = { "$file", "-g", "-o", "$target" },
      compiler = "rustc",
      mode = "compiled",
      run_args = {},
      run_command = "$target",
    },
    zig = {
      compile_args = { "build-exe", "$file", "-femit-bin=$target" },
      compiler = "zig",
      mode = "compiled",
      run_args = {},
      run_command = "$target",
    },
  },
}

function M.defaults()
  return util.deepcopy(defaults)
end

function M.resolve(user_config)
  if type(user_config) ~= "table" then
    return M.defaults()
  end

  return util.merge(defaults, user_config or {})
end

return M
