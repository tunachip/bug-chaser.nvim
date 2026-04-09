local config = require("bug_chaser.config")
local runner = require("bug_chaser.runner")

local M = {
  _config = nil,
}

function M.setup(user_config)
  M._config = config.resolve(user_config)
end

function M.get_config()
  if type(M._config) ~= "table" then
    M._config = config.resolve(M._config)
  end

  M._config = config.resolve(M._config)
  return M._config
end

function M.run_command(opts)
  runner.run(vim.api.nvim_get_current_buf(), opts or {}, M.get_config())
end

return M
