local util = require("bug_chaser.util")

local M = {}

local defaults = {
  cwd = "buffer_dir",
  notify_on_success = false,
  open_command = "split",
  diagnostics = {
    virtual_lines = {
      enabled = false,
      severity = { min = vim.diagnostic.severity.WARN },
      source = "if_many",
      trailing_pad = 18,
    },
  },
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
      args = function(vars)
        local argv = util.default_python_argv(vars)
        table.remove(argv, 1)
        return argv
      end,
      command = function(vars)
        return util.default_python_argv(vars)[1]
      end,
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
    javascriptreact = {
      args = { "$file" },
      command = "tsx",
      mode = "command",
    },
    typescript = {
      args = { "$file" },
      command = { "node", "--experimental-strip-types" },
      mode = "command",
    },
    typescriptreact = {
      args = { "$file" },
      command = "tsx",
      mode = "command",
    },
    sh = {
      args = { "$file" },
      command = "bash",
      mode = "command",
    },
    bash = {
      args = { "$file" },
      command = "bash",
      mode = "command",
    },
    zsh = {
      args = { "$file" },
      command = "bash",
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
      commands = {
        ["cargo-run"] = {
          args = { "run" },
          capture = "none",
          command = "cargo",
          cwd = function(ctx)
            local start = util.dirname(ctx.source_path or ctx.exec_source_path or "")
            local manifest = util.find_up("Cargo.toml", start)
            if manifest then
              return util.dirname(manifest)
            end

            return ctx.default_cwd
          end,
          description = "Run the current Cargo package",
          mode = "command",
        },
        ["current-buffer"] = {
          compile_args = { "--crate-name", "bug_chaser", "$file", "-g", "-o", "$target" },
          compiler = "rustc",
          description = "Compile only the current Rust file",
          mode = "compiled",
          run_args = {},
          run_command = "$target",
        },
      },
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

local function language_base(language_config)
  local base = {}

  for key, value in pairs(language_config or {}) do
    if key ~= "commands" then
      base[key] = util.deepcopy(value)
    end
  end

  return base
end

function M.commands_for_language(language_config)
  if type(language_config) ~= "table" then
    return {}
  end

  if type(language_config.commands) ~= "table" or vim.tbl_isempty(language_config.commands) then
    local command = util.deepcopy(language_config)
    command.capture = command.capture or "buffer"
    command.display_name = command.display_name or "default"
    command.name = command.name or "default"
    return { command }
  end

  local base = language_base(language_config)
  local names = vim.tbl_keys(language_config.commands)
  table.sort(names)

  local commands = {}

  for _, name in ipairs(names) do
    local command = language_config.commands[name]
    if type(command) == "table" then
      local resolved = util.merge(base, command)
      resolved.capture = resolved.capture or "buffer"
      resolved.display_name = resolved.display_name or name
      resolved.name = name
      table.insert(commands, resolved)
    end
  end

  return commands
end

function M.find_command(language_config, name)
  local commands = M.commands_for_language(language_config)

  if not name or name == "" then
    return nil, commands
  end

  for _, command in ipairs(commands) do
    if command.name == name then
      return command, commands
    end
  end

  return nil, commands
end

return M
