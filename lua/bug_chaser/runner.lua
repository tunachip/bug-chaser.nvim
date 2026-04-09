local config_module = require("bug_chaser.config")
local parser = require("bug_chaser.parser")
local terminal = require("bug_chaser.terminal")
local ui = require("bug_chaser.ui")
local util = require("bug_chaser.util")

local M = {}

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "bug-chaser" })
end

local function resolve_cwd(config, language, language_config, source_path, exec_source_path)
  local cwd = language_config.cwd
  if cwd == nil then
    cwd = config.cwd
  end

  if type(cwd) == "function" then
    return cwd({
      exec_source_path = exec_source_path,
      language = language,
      language_config = language_config,
      source_path = source_path,
    })
  end

  if cwd == "buffer_dir" and source_path then
    return util.dirname(source_path)
  end

  if cwd == "source_dir" and exec_source_path then
    return util.dirname(exec_source_path)
  end

  if type(cwd) == "string" and cwd ~= "" and cwd ~= "cwd" and cwd ~= "buffer_dir" and cwd ~= "source_dir" then
    return util.resolve_path(cwd, vim.fn.getcwd())
  end

  return vim.fn.getcwd()
end

local function cleanup(paths)
  for _, path in ipairs(paths or {}) do
    util.unlink(path)
  end
end

local function run_process(argv, opts, callback)
  if not argv or #argv == 0 then
    callback({
      code = 1,
      output = "No command configured",
      stderr = "No command configured",
      stdout = "",
    })
    return
  end

  local ok, err = pcall(vim.system, argv, {
    cwd = opts.cwd,
    text = true,
  }, vim.schedule_wrap(function(result)
    callback({
      code = result.code,
      output = util.combine_output(result.stdout, result.stderr),
      stderr = result.stderr or "",
      stdout = result.stdout or "",
    })
  end))

  if not ok then
    callback({
      code = 1,
      output = tostring(err),
      stderr = tostring(err),
      stdout = "",
    })
  end
end

local function build_execution(bufnr, opts, config)
  local language = util.detect_language(bufnr)
  if not language then
    return nil, "Unable to determine the current buffer language"
  end

  local language_config = config.languages[language]
  if not language_config then
    return nil, string.format("No runner is configured for %s", language)
  end

  local source_path = util.get_buffer_path(bufnr)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local has_range = (opts.range or 0) > 0
  local start_line = has_range and opts.line1 or 1
  local end_line = has_range and opts.line2 or line_count
  local use_temp_source = has_range or vim.bo[bufnr].modified or source_path == nil
  local temp_source_path = nil
  local cleanup_paths = {}
  local exec_source_path = source_path
  local remap = nil

  if use_temp_source then
    temp_source_path = util.make_temp_source_path(source_path, language)
    local ok, err = util.write_file(temp_source_path, util.get_buffer_text(bufnr, start_line, end_line))
    if not ok then
      return nil, err
    end

    exec_source_path = temp_source_path
    table.insert(cleanup_paths, temp_source_path)
    remap = {
      line_offset = has_range and (start_line - 1) or 0,
      source_bufnr = bufnr,
      source_path = source_path,
      temp_path = util.normalize_path(temp_source_path),
    }
  end

  if not exec_source_path or exec_source_path == "" then
    return nil, "The current buffer has no executable source path"
  end

  local cwd = resolve_cwd(config, language, language_config, source_path, exec_source_path)
  local vars = {
    cwd = cwd,
    file = exec_source_path,
    selection_end = end_line,
    selection_start = start_line,
    source_dir = util.dirname(source_path or exec_source_path),
    source_name = util.basename(source_path or exec_source_path),
    target = "",
  }

  local compile_argv = nil
  local run_argv = nil

  if language_config.mode == "compiled" then
    local target_path = util.make_temp_target_path(source_path or exec_source_path)
    vars.target = target_path
    table.insert(cleanup_paths, target_path)

    compile_argv = util.expand_argv(language_config.compiler, language_config.compile_args or {}, vars)
    run_argv = util.expand_argv(language_config.run_command or "$target", language_config.run_args or {}, vars)
  else
    run_argv = util.expand_argv(language_config.command, language_config.args or {}, vars)
  end

  return {
    cleanup_paths = cleanup_paths,
    compile_argv = compile_argv,
    cwd = cwd,
    language = language,
    origin_winid = vim.api.nvim_get_current_win(),
    parser_context = {
      cwd = cwd,
      remap = remap,
      source_bufnr = bufnr,
      source_path = source_path,
    },
    run_argv = run_argv,
  }
end

local function present_failure(execution, result, config)
  local parsed = parser.parse(execution.language, result.output, execution.parser_context)

  if parsed.selected_frame and ui.show(parsed.selected_frame, parsed.explanation, config, {
    winid = execution.origin_winid,
  }) then
    return
  end

  local message = parsed.explanation
  if not message or message == "" then
    message = util.truncate(result.output ~= "" and result.output or "Command failed", 240)
  end

  notify(message, vim.log.levels.ERROR)
end

function M.run(bufnr, opts, config)
  config = config_module.resolve(config)

  local execution, err = build_execution(bufnr, opts, config)
  if not execution then
    notify(err, vim.log.levels.ERROR)
    return
  end

  local function on_success()
    ui.clear()
    if config.notify_on_success then
      notify(string.format("%s completed without a parsable failure", execution.language))
    end
  end

  local function finish(result)
    if result.code == 0 then
      on_success()
    else
      present_failure(execution, result, config)
    end
    cleanup(execution.cleanup_paths)
  end

  if not execution.run_argv or #execution.run_argv == 0 then
    notify("No command configured", vim.log.levels.ERROR)
    cleanup(execution.cleanup_paths)
    return
  end

  local function run_in_terminal()
    local ok, terminal_err = terminal.run(execution.run_argv, {
      cwd = execution.cwd,
      focus = config.terminal.focus,
      height = config.terminal.height,
      name = config.terminal.name,
      origin_winid = execution.origin_winid,
      position = config.terminal.position,
    }, finish)

    if not ok then
      notify(terminal_err, vim.log.levels.ERROR)
      cleanup(execution.cleanup_paths)
    end
  end

  if execution.compile_argv then
    run_process(execution.compile_argv, { cwd = execution.cwd }, function(compile_result)
      if compile_result.code ~= 0 then
        finish(compile_result)
        return
      end

      run_in_terminal()
    end)
    return
  end

  run_in_terminal()
end

return M
