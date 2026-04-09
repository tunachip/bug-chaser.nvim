local M = {}

local namespace = vim.api.nvim_create_namespace("bug_chaser")

local function build_virtual_line(text, highlight, winid)
  local width = vim.api.nvim_win_get_width(winid)
  local text_width = vim.fn.strdisplaywidth(text)
  local padding = math.max(width - text_width, 0)

  local chunks = {
    { text, highlight },
  }

  if padding > 0 then
    table.insert(chunks, { string.rep(" ", padding), highlight })
  end

  return { chunks }
end

function M.clear(bufnr)
  if bufnr then
    if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
      vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
    end
    return
  end

  for _, loaded in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(loaded) and vim.api.nvim_buf_is_loaded(loaded) then
      vim.api.nvim_buf_clear_namespace(loaded, namespace, 0, -1)
    end
  end
end

function M.show(frame, explanation, config, opts)
  if not frame then
    return false
  end

  M.clear()

  local target_winid = opts and opts.winid or nil
  if target_winid and vim.api.nvim_win_is_valid(target_winid) then
    vim.api.nvim_set_current_win(target_winid)
  end

  local bufnr
  if frame.source_bufnr and vim.api.nvim_buf_is_valid(frame.source_bufnr) then
    vim.api.nvim_set_current_buf(frame.source_bufnr)
    bufnr = frame.source_bufnr
  elseif frame.path and frame.path ~= "" then
    local command = config.open_command or "split"
    vim.cmd(string.format("%s %s", command, vim.fn.fnameescape(frame.path)))
    bufnr = vim.api.nvim_get_current_buf()
  else
    return false
  end

  local line_count = math.max(vim.api.nvim_buf_line_count(bufnr), 1)
  local line = math.max(1, math.min(frame.lnum or 1, line_count))
  local col = math.max((frame.col or 1) - 1, 0)
  local winid = vim.api.nvim_get_current_win()
  local highlight = config.virtual_line.highlight or "DiagnosticVirtualTextError"
  local text = (config.virtual_line.prefix or "") .. explanation

  vim.api.nvim_win_set_cursor(winid, { line, col })

  vim.api.nvim_buf_set_extmark(bufnr, namespace, line - 1, 0, {
    hl_mode = "combine",
    virt_lines = build_virtual_line(text, highlight, winid),
    virt_lines_above = config.virtual_line.above ~= false,
  })

  return true
end

return M
