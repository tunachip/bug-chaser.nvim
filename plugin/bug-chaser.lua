if vim.g.loaded_bug_chaser == 1 then
  return
end

vim.g.loaded_bug_chaser = 1

vim.api.nvim_create_user_command("BugChaserRun", function(opts)
  require("bug_chaser").run_command(opts)
end, {
  complete = function(arg_lead)
    return require("bug_chaser").complete_command_names(arg_lead)
  end,
  desc = "Run the current buffer, a selected range, or a named bug-chaser command",
  nargs = "*",
  range = true,
})

vim.api.nvim_create_user_command("Run", function(opts)
  require("bug_chaser").run_command(opts)
end, {
  complete = function(arg_lead)
    return require("bug_chaser").complete_command_names(arg_lead)
  end,
  desc = "Run the current buffer, a selected range, or a named command",
  nargs = "*",
  range = true,
})

vim.api.nvim_create_user_command("BugChaserToggleDiagnosticVirtualLines", function()
  require("bug_chaser").toggle_diagnostic_virtual_lines()
end, {
  desc = "Toggle bug-chaser diagnostic virtual lines",
})
