local M = {}

local namespace = vim.api.nvim_create_namespace("bug_chaser_diagnostic_virtual_lines")
local handler_name = "bug_chaser_virtual_lines"

local default_palette = {
  error = { fg = "#ffffff", bg = "#550000" },
  warn = { fg = "#ffffff", bg = "#555500" },
  info = { fg = "#ffffff", bg = "#000055" },
  hint = { fg = "#ffffff", bg = "#005555" },
}

local state = {
  installed = false,
  opts = nil,
}

local function wrap_message(text, max_width)
  local out = {}
  local width = math.max(20, tonumber(max_width) or 20)

  for _, paragraph in ipairs(vim.split(text or "", "\n", { plain = true })) do
    local line = ""
    for word in paragraph:gmatch("%S+") do
      if line == "" then
        line = word
      elseif #line + 1 + #word <= width then
        line = line .. " " .. word
      else
        table.insert(out, line)
        line = word
      end
    end
    if line ~= "" then
      table.insert(out, line)
    end
  end

  if #out == 0 then
    out[1] = ""
  end

  return out
end

local function severity_key(severity)
  if severity == vim.diagnostic.severity.ERROR then
    return "error"
  elseif severity == vim.diagnostic.severity.WARN then
    return "warn"
  elseif severity == vim.diagnostic.severity.INFO then
    return "info"
  end
  return "hint"
end

local function content_group(severity)
  local key = severity_key(severity)
  return "BugChaserDiagnosticVirtualLine" .. key:sub(1, 1):upper() .. key:sub(2)
end

local function fill_group(severity)
  local key = severity_key(severity)
  return "BugChaserDiagnosticVirtualFill" .. key:sub(1, 1):upper() .. key:sub(2)
end

local function refresh_highlights()
  for key, colors in pairs(default_palette) do
    local suffix = key:sub(1, 1):upper() .. key:sub(2)
    vim.api.nvim_set_hl(0, "BugChaserDiagnosticVirtualLine" .. suffix, {
      fg = colors.fg,
      bg = colors.bg,
    })
    vim.api.nvim_set_hl(0, "BugChaserDiagnosticVirtualFill" .. suffix, {
      fg = colors.bg,
      bg = colors.bg,
    })
  end
end

local function format_message(diagnostic, opts, many_sources)
  local msg = (diagnostic.message or ""):gsub("%s+", " ")
  local source_mode = opts.source
  if diagnostic.source and (source_mode == "always" or (source_mode == "if_many" and many_sources)) then
    return string.format("%s: %s", diagnostic.source, msg)
  end
  return msg
end

local function clear_buffer(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
  end
end

local function refresh_visible_diagnostics()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      vim.diagnostic.hide(nil, bufnr)
      vim.diagnostic.show(nil, bufnr)
    end
  end
end

local function install_handler()
  if vim.diagnostic.handlers[handler_name] then
    return
  end

  vim.diagnostic.handlers[handler_name] = {
    show = function(_, bufnr, diagnostics, opts)
      clear_buffer(bufnr)
      if not diagnostics or vim.tbl_isempty(diagnostics) then
        return
      end

      local winid = vim.fn.bufwinid(bufnr)
      if winid == -1 then
        return
      end

      local win_width = vim.api.nvim_win_get_width(winid)
      local wininfo = vim.fn.getwininfo(winid)[1] or {}
      local textoff = tonumber(wininfo.textoff) or 0

      local by_source = {}
      for _, diagnostic in ipairs(diagnostics) do
        by_source[diagnostic.source or ""] = true
      end
      local many_sources = vim.tbl_count(by_source) > 1

      for _, diagnostic in ipairs(diagnostics) do
        local anchor_col = diagnostic.col or 0
        local usable = math.max(20, win_width - textoff - anchor_col - 14)
        local msg = format_message(diagnostic, opts, many_sources)
        local wrapped = wrap_message(msg, usable)
        local virt_lines = {}
        local trailing_pad = tonumber(opts.trailing_pad) or 18
        local content_hl = content_group(diagnostic.severity)
        local fill_hl = fill_group(diagnostic.severity)

        for index, line in ipairs(wrapped) do
          local prefix = (index == 1) and "└ " or "  "
          local left_fill = math.max(0, textoff + anchor_col)
          local content = prefix .. line
          local fill = math.max(0, usable - vim.fn.strdisplaywidth(content) + trailing_pad)
          table.insert(virt_lines, {
            { string.rep("█", left_fill), fill_hl },
            { content, content_hl },
            { string.rep("█", fill), fill_hl },
          })
        end

        if #virt_lines > 0 then
          vim.api.nvim_buf_set_extmark(bufnr, namespace, diagnostic.lnum, 0, {
            virt_lines = virt_lines,
            virt_lines_above = false,
            virt_lines_leftcol = true,
          })
        end
      end
    end,
    hide = function(_, bufnr)
      clear_buffer(bufnr)
    end,
  }
end

function M.setup(config)
  local opts = (((config or {}).diagnostics or {}).virtual_lines or {})
  state.opts = vim.deepcopy(opts)

  refresh_highlights()
  install_handler()

  local enabled = opts.enabled == true
  vim.diagnostic.config({
    virtual_text = enabled and false or vim.diagnostic.config().virtual_text,
    virtual_lines = enabled and false or vim.diagnostic.config().virtual_lines,
    [handler_name] = enabled and {
      source = opts.source or "if_many",
      severity = opts.severity or { min = vim.diagnostic.severity.WARN },
      trailing_pad = opts.trailing_pad or 18,
    } or false,
  })

  if not state.installed then
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = vim.api.nvim_create_augroup("BugChaserDiagnosticVirtualLines", { clear = true }),
      callback = function()
        refresh_highlights()
      end,
      desc = "Refresh bug-chaser diagnostic virtual line highlights",
    })
  end

  state.installed = true
  if enabled then
    refresh_visible_diagnostics()
  end
end

function M.toggle()
  state.opts = state.opts or {}
  state.opts.enabled = not state.opts.enabled
  M.setup({
    diagnostics = {
      virtual_lines = state.opts,
    },
  })
  return state.opts.enabled
end

return M
