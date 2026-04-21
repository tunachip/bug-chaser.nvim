local util = require("bug_chaser.util")

local M = {}

local state = {
  bufnr = nil,
  jobid = nil,
  run_id = 0,
  winid = nil,
}

local function valid_buffer(bufnr)
  return bufnr and vim.api.nvim_buf_is_valid(bufnr)
end

local function valid_window(winid)
  return winid and vim.api.nvim_win_is_valid(winid)
end

local function job_running(jobid)
  if not jobid then
    return false
  end

  return vim.fn.jobwait({ jobid }, 0)[1] == -1
end

local function stop_active_job()
  if job_running(state.jobid) then
    pcall(vim.fn.jobstop, state.jobid)
  end

  state.jobid = nil
end

local function terminal_output(bufnr)
  if not valid_buffer(bufnr) then
    return ""
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  while #lines > 0 and vim.trim(lines[#lines]):match("^%[Process exited") do
    table.remove(lines)
  end

  return util.strip_ansi(table.concat(lines, "\n"))
end

local function ensure_window(opts)
  local height = math.max(1, tonumber(opts.height) or 12)

  if valid_window(state.winid) then
    vim.api.nvim_set_current_win(state.winid)
    return state.winid
  end

  vim.cmd(string.format("%s %dnew", opts.position or "botright", height))
  state.winid = vim.api.nvim_get_current_win()
  vim.wo[state.winid].number = false
  vim.wo[state.winid].relativenumber = false
  vim.wo[state.winid].winfixheight = true

  return state.winid
end

local function prepare_buffer(opts)
  local previous_bufnr = state.bufnr

  vim.cmd("enew")

  local bufnr = vim.api.nvim_get_current_buf()
  if valid_buffer(previous_bufnr) and previous_bufnr ~= bufnr then
    pcall(vim.api.nvim_buf_delete, previous_bufnr, { force = true })
  end

  pcall(vim.api.nvim_buf_set_name, bufnr, opts.name or "bug-chaser://runner")
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  vim.b[bufnr].bug_chaser_terminal = true

  state.bufnr = bufnr

  return bufnr
end

function M.run(argv, opts, callback)
  if not argv or #argv == 0 then
    return nil, "No command configured"
  end

  opts = opts or {}
  local origin_winid = opts.origin_winid

  stop_active_job()

  state.run_id = state.run_id + 1
  local run_id = state.run_id

  local function open_terminal()
    ensure_window(opts)
    local bufnr = prepare_buffer(opts)
    local jobid = vim.fn.termopen(argv, {
      cwd = opts.cwd,
      on_exit = vim.schedule_wrap(function(_, code, _)
        if run_id ~= state.run_id then
          return
        end

        state.jobid = nil

        callback({
          bufnr = bufnr,
          code = code,
          output = terminal_output(bufnr),
          winid = state.winid,
        })
      end),
    })

    if jobid <= 0 then
      error("Failed to start bug-chaser terminal job")
    end

    state.jobid = jobid

    if opts.focus then
      vim.cmd("startinsert")
    end

    return true
  end

  local ok, result = pcall(function()
    if origin_winid and valid_window(origin_winid) then
      return vim.api.nvim_win_call(origin_winid, open_terminal)
    end

    return open_terminal()
  end)

  if not ok then
    return nil, tostring(result)
  end

  if opts.focus and valid_window(state.winid) then
    vim.api.nvim_set_current_win(state.winid)
    vim.cmd("startinsert")
  elseif not opts.focus and origin_winid and valid_window(origin_winid) then
    vim.api.nvim_set_current_win(origin_winid)
  end

  return {
    bufnr = state.bufnr,
    winid = state.winid,
  }
end

function M.get_state()
  return vim.deepcopy(state)
end

return M
