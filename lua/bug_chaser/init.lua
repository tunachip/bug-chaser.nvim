local config = require("bug_chaser.config")
local diagnostics = require("bug_chaser.diagnostics")
local runner = require("bug_chaser.runner")

local M = {
  _config = nil,
}

function M.setup(user_config)
  M._config = config.resolve(user_config)
  diagnostics.setup(M._config)
end

function M.get_config()
  if type(M._config) ~= "table" then
    M._config = config.resolve(M._config)
  end

  M._config = config.resolve(M._config)
  return M._config
end

function M.run_command(opts)
  opts = vim.deepcopy(opts or {})

  if type(opts.args) == "string" then
    local command_name = vim.trim(opts.args)
    if command_name ~= "" then
      opts.command_name = command_name
    end
  end

  runner.run(vim.api.nvim_get_current_buf(), opts, M.get_config())
end

function M.complete_command_names(arg_lead)
  return runner.complete_command_names(vim.api.nvim_get_current_buf(), arg_lead or "", M.get_config())
end

function M.toggle_diagnostic_virtual_lines()
  local enabled = diagnostics.toggle()
  M._config = M.get_config()
  M._config.diagnostics = M._config.diagnostics or {}
  M._config.diagnostics.virtual_lines = M._config.diagnostics.virtual_lines or {}
  M._config.diagnostics.virtual_lines.enabled = enabled
end

return M
