if vim.g.loaded_bug_chaser == 1 then
  return
end

vim.g.loaded_bug_chaser = 1

vim.api.nvim_create_user_command("BugChaserRun", function(opts)
  require("bug_chaser").run_command(opts)
end, {
  desc = "Run the current buffer or a selected range through bug-chaser",
  range = true,
})
