local util = require("bug_chaser.util")

local M = {}

local function split_lines(output)
  return vim.split(output or "", "\n", { plain = true, trimempty = false })
end

local function last_non_empty(lines)
  for index = #lines, 1, -1 do
    local line = lines[index]
    if line and line ~= "" then
      return line
    end
  end
end

local function caret_column(lines, index)
  for offset = 1, 3 do
    local line = lines[index + offset]
    if not line then
      break
    end

    local col = line:find("%^", 1, false)
    if col then
      return col
    end
  end
end

local function add_frame(frames, path, lnum, col, opts)
  if not path or path == "" then
    return
  end

  path = vim.trim(path)

  if not util.looks_like_path(path) then
    return
  end

  local frame = {
    col = tonumber(col) or 1,
    function_name = opts and opts.function_name or nil,
    is_diagnostic = opts and (opts.is_diagnostic or opts.message ~= nil) or false,
    lnum = tonumber(lnum),
    message = opts and opts.message or nil,
    path = path,
    raw = opts and opts.raw or nil,
  }

  local last = frames[#frames]
  if last and last.path == frame.path and last.lnum == frame.lnum and last.col == frame.col then
    last.function_name = last.function_name or frame.function_name
    last.is_diagnostic = last.is_diagnostic or frame.is_diagnostic
    last.message = last.message or frame.message
    last.raw = last.raw or frame.raw
    return
  end

  table.insert(frames, frame)
end

local function parse_generic_lines(lines)
  local frames = {}
  local summary = nil

  for index, line in ipairs(lines) do
    local handled = false

    local arrow_path, arrow_lnum, arrow_col = line:match("^%s*%-%->%s+(.-):(%d+):(%d+)$")
    if arrow_path and util.looks_like_path(arrow_path) then
      add_frame(frames, arrow_path, arrow_lnum, arrow_col, {
        is_diagnostic = true,
        raw = line,
      })
      handled = true
    else
      local arrow_simple_path, arrow_simple_lnum = line:match("^%s*%-%->%s+(.-):(%d+)$")
      if arrow_simple_path and util.looks_like_path(arrow_simple_path) then
        add_frame(frames, arrow_simple_path, arrow_simple_lnum, 1, {
          is_diagnostic = true,
          raw = line,
        })
        handled = true
      end
    end

    if not handled then
      local path, lnum, col, message = line:match("^%s*(.-):(%d+):(%d+):%s*(.+)$")
      if path and util.looks_like_path(path) then
        add_frame(frames, path, lnum, col, { message = message, raw = line })
        summary = summary or { type = "error", message = message }
      else
        local simple_path, simple_lnum, simple_message = line:match("^%s*(.-):(%d+):%s*(.+)$")
        if simple_path and util.looks_like_path(simple_path) then
          add_frame(frames, simple_path, simple_lnum, 1, { message = simple_message, raw = line })
          summary = summary or { type = "error", message = simple_message }
        else
          local bare_path, bare_lnum, bare_col = line:match("^%s*(.-):(%d+):(%d+)$")
          if bare_path and util.looks_like_path(bare_path) then
            add_frame(frames, bare_path, bare_lnum, bare_col, {
              is_diagnostic = true,
              raw = line,
            })
          else
            local simple_bare_path, simple_bare_lnum = line:match("^%s*(.-):(%d+)$")
            if simple_bare_path and util.looks_like_path(simple_bare_path) then
              local col = caret_column(lines, index)
              add_frame(frames, simple_bare_path, simple_bare_lnum, col or 1, {
                is_diagnostic = col ~= nil,
                raw = line,
              })
            end
          end
        end
      end
    end
  end

  return frames, summary
end

local function parse_python(lines)
  local frames = {}
  local summary = nil

  for index, line in ipairs(lines) do
    local path, lnum, function_name = line:match('^%s*File "([^"]+)", line (%d+), in (.+)$')
    if path then
      add_frame(frames, path, lnum, 1, { function_name = function_name, raw = line })
    else
      local syntax_path, syntax_lnum = line:match('^%s*File "([^"]+)", line (%d+)$')
      if syntax_path then
        add_frame(frames, syntax_path, syntax_lnum, caret_column(lines, index) or 1, {
          is_diagnostic = true,
          raw = line,
        })
      end
    end
  end

  for index = #lines, 1, -1 do
    local error_type, message = lines[index]:match("^([%w_.]+):%s*(.+)$")
    if error_type then
      summary = { type = error_type, message = message }
      break
    end
  end

  if #frames == 0 then
    local generic_frames, generic_summary = parse_generic_lines(lines)
    frames = generic_frames
    summary = summary or generic_summary
  end

  return {
    frames = frames,
    kind = "runtime",
    preferred = "last",
    summary = summary,
  }
end

local function parse_lua(lines)
  local frames = {}
  local summary = nil

  for _, line in ipairs(lines) do
    local path, lnum, message = line:match("^lua:%s+(.-%.lua):(%d+):%s*(.+)$")
    if path then
      add_frame(frames, path, lnum, 1, { message = message, raw = line })
      summary = summary or { type = "LuaError", message = message }
    end

    local stack_path, stack_lnum, function_name = line:match("^%s*(.-%.lua):(%d+): in (.+)$")
    if stack_path then
      add_frame(frames, stack_path, stack_lnum, 1, { function_name = function_name, raw = line })
    end
  end

  if #frames == 0 then
    local generic_frames, generic_summary = parse_generic_lines(lines)
    frames = generic_frames
    summary = summary or generic_summary
  end

  return {
    frames = frames,
    kind = "runtime",
    preferred = "first",
    summary = summary,
  }
end

local function parse_javascript_like(lines)
  local frames = {}
  local summary = nil

  for _, line in ipairs(lines) do
    local path, lnum, col = line:match("^%s*at%s+.-%((.-):(%d+):(%d+)%)$")
    if path then
      add_frame(frames, path, lnum, col, { raw = line })
    else
      local direct_path, direct_lnum, direct_col = line:match("^%s*at%s+(.-):(%d+):(%d+)$")
      if direct_path then
        add_frame(frames, direct_path, direct_lnum, direct_col, { raw = line })
      end
    end

    if not summary then
      local error_type, message = line:match("^([%w_.]+):%s*(.+)$")
      if error_type and line:match("Error") then
        summary = { type = error_type, message = message }
      elseif line:match("error TS%d+") then
        summary = { type = "TypeScriptError", message = line }
      end
    end
  end

  local generic_frames, generic_summary = parse_generic_lines(lines)
  for _, frame in ipairs(generic_frames) do
    add_frame(frames, frame.path, frame.lnum, frame.col, {
      function_name = frame.function_name,
      message = frame.message,
      raw = frame.raw,
    })
  end

  summary = summary or generic_summary

  if not summary then
    local tail = last_non_empty(lines)
    if tail then
      summary = { type = "Error", message = tail }
    end
  end

  return {
    frames = frames,
    kind = "runtime",
    preferred = "first",
    summary = summary,
  }
end

local function parse_compiler_like(lines)
  local frames, summary = parse_generic_lines(lines)

  if not summary then
    for _, line in ipairs(lines) do
      local message = line:match("fatal error:%s*(.+)$") or line:match("error:%s*(.+)$")
      if message then
        summary = { type = "CompilerError", message = message }
        break
      end
    end
  end

  return {
    frames = frames,
    kind = "compile",
    preferred = "first",
    summary = summary,
  }
end

local function parse_go(lines)
  local frames = {}
  local summary = nil

  for _, line in ipairs(lines) do
    local panic_message = line:match("^panic:%s*(.+)$")
    if panic_message and not summary then
      summary = { type = "panic", message = panic_message }
    end

    local path, lnum, col, message = line:match("^%s*(.-%.go):(%d+):(%d+):%s*(.+)$")
    if path then
      add_frame(frames, path, lnum, col, { message = message, raw = line })
    else
      local stack_path, stack_lnum = line:match("^%s*(.-%.go):(%d+)")
      if stack_path then
        add_frame(frames, stack_path, stack_lnum, 1, { raw = line })
      end
    end
  end

  if #frames == 0 then
    local generic_frames, generic_summary = parse_generic_lines(lines)
    frames = generic_frames
    summary = summary or generic_summary
  end

  return {
    frames = frames,
    kind = "runtime",
    preferred = "first",
    summary = summary,
  }
end

local function parse_rust(lines)
  local frames = {}
  local summary = nil

  for _, line in ipairs(lines) do
    local compile_message = line:match("^error:?%s*(.+)$") or line:match("^error%[[^%]]+%]:%s*(.+)$")
    if compile_message and not summary then
      summary = { type = "CompilerError", message = compile_message }
    end

    local panic_prefix, path, lnum, col = line:match("^(.*), (.-%.rs):(%d+):(%d+)$")
    if panic_prefix and panic_prefix:match("^thread '.*' panicked at ") then
      local panic_message = panic_prefix:gsub("^thread '.*' panicked at ", "", 1)
      add_frame(frames, path, lnum, col, { message = panic_message, raw = line })
      summary = summary or { type = "panic", message = panic_message }
    end

    local backtrace_path, backtrace_lnum, backtrace_col = line:match("at%s+(.-%.rs):(%d+):(%d+)")
    if backtrace_path then
      add_frame(frames, backtrace_path, backtrace_lnum, backtrace_col, { raw = line })
    end

    local compile_path, compile_lnum, compile_col, message = line:match("^%s*(.-%.rs):(%d+):(%d+):%s*(.+)$")
    if compile_path then
      add_frame(frames, compile_path, compile_lnum, compile_col, { message = message, raw = line })
      summary = summary or { type = "CompilerError", message = message }
    end
  end

  if #frames == 0 then
    local generic_frames, generic_summary = parse_generic_lines(lines)
    frames = generic_frames
    summary = summary or generic_summary
  end

  return {
    frames = frames,
    kind = "runtime",
    preferred = "first",
    summary = summary,
  }
end

local function parse_zig(lines)
  local frames = {}
  local summary = nil

  for _, line in ipairs(lines) do
    local panic_message = line:match("^thread%s+[%d]+%s+panic:%s*(.+)$") or line:match("^panic:%s*(.+)$")
    if panic_message and not summary then
      summary = { type = "panic", message = panic_message }
    end

    local path, lnum, col, message = line:match("^%s*(.-%.zig):(%d+):(%d+):%s*(.+)$")
    if path then
      add_frame(frames, path, lnum, col, { message = message, raw = line })
      if not summary and message:match("^error:") then
        summary = { type = "CompilerError", message = message }
      end
    end
  end

  if #frames == 0 then
    local generic_frames, generic_summary = parse_generic_lines(lines)
    frames = generic_frames
    summary = summary or generic_summary
  end

  return {
    frames = frames,
    kind = "runtime",
    preferred = "first",
    summary = summary,
  }
end

local parsers = {
  c = parse_compiler_like,
  cpp = parse_compiler_like,
  go = parse_go,
  javascript = parse_javascript_like,
  lua = parse_lua,
  python = parse_python,
  rust = parse_rust,
  typescript = parse_javascript_like,
  zig = parse_zig,
}

local function apply_context(parsed, context)
  context = context or {}

  for _, frame in ipairs(parsed.frames or {}) do
    frame.path = util.resolve_path(frame.path, context.cwd)

    if context.remap and frame.path and util.same_path(frame.path, context.remap.temp_path) then
      frame.lnum = (frame.lnum or 1) + (context.remap.line_offset or 0)
      frame.source_bufnr = context.remap.source_bufnr

      if context.remap.source_path then
        frame.path = context.remap.source_path
      end
    elseif context.source_path and frame.path and util.same_path(frame.path, context.source_path) then
      frame.source_bufnr = context.source_bufnr
    end
  end

  return parsed
end

local function choose_frame(parsed)
  local frames = {}

  for _, frame in ipairs(parsed.frames or {}) do
    if frame.lnum then
      table.insert(frames, frame)
    end
  end

  if #frames == 0 then
    frames = parsed.frames or {}
  end

  if #frames == 0 then
    return nil
  end

  local diagnostic_frames = {}
  for _, frame in ipairs(frames) do
    if frame.is_diagnostic then
      table.insert(diagnostic_frames, frame)
    end
  end

  if #diagnostic_frames > 0 then
    frames = diagnostic_frames
  end

  local best_frames = {}
  local best_score = nil

  for _, frame in ipairs(frames) do
    local score = 0

    if frame.is_diagnostic then
      score = score + 200
    end

    if frame.message then
      score = score + 75
    end

    if frame.source_bufnr then
      score = score + 50
    end

    if frame.path and util.is_user_path(frame.path) then
      score = score + 25
    end

    if frame.col and frame.col > 1 then
      score = score + 5
    end

    if frame.function_name then
      score = score + 2
    end

    if best_score == nil or score > best_score then
      best_score = score
      best_frames = { frame }
    elseif score == best_score then
      table.insert(best_frames, frame)
    end
  end

  if parsed.preferred == "last" then
    return best_frames[#best_frames]
  end

  return best_frames[1]
end

local function build_explanation(language, parsed, frame)
  local summary = parsed.summary or {}
  local explanation

  if summary.type and summary.message then
    explanation = string.format("%s %s: %s", language, summary.type, summary.message)
  elseif summary.message then
    explanation = string.format("%s: %s", language, summary.message)
  elseif summary.type then
    explanation = string.format("%s %s", language, summary.type)
  else
    explanation = string.format("%s command failed", language)
  end

  if frame and frame.function_name then
    explanation = explanation .. string.format(" in %s", frame.function_name)
  end

  if frame then
    local location = frame.path and util.basename(frame.path) or nil
    if location and location ~= "" then
      explanation = string.format("%s at %s:%d", explanation, location, frame.lnum or 1)
      if frame.col and frame.col > 1 then
        explanation = explanation .. string.format(":%d", frame.col)
      end
    elseif frame.lnum then
      explanation = explanation .. string.format(" at line %d", frame.lnum)
    end
  end

  return util.truncate(explanation, 240)
end

function M.parse(language, output, context)
  local lines = split_lines(output)
  local parser = parsers[language] or parse_compiler_like
  local parsed = parser(lines)

  parsed.raw = output or ""
  parsed = apply_context(parsed, context)
  parsed.selected_frame = choose_frame(parsed)
  parsed.explanation = build_explanation(language, parsed, parsed.selected_frame)

  return parsed
end

return M
