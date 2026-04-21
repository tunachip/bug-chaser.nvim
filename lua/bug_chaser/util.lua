local uv = vim.uv or vim.loop

local M = {}

local ft_map = {
  c = "c",
  cc = "cpp",
  cpp = "cpp",
  cxx = "cpp",
  ["c++"] = "cpp",
  go = "go",
  javascript = "javascript",
  javascriptreact = "javascript",
  lua = "lua",
  python = "python",
  rust = "rust",
  typescript = "typescript",
  typescriptreact = "typescript",
  zig = "zig",
}

local ext_map = {
  c = "c",
  cc = "cpp",
  cjs = "javascript",
  cpp = "cpp",
  cts = "typescript",
  cxx = "cpp",
  go = "go",
  js = "javascript",
  lua = "lua",
  mjs = "javascript",
  mts = "typescript",
  py = "python",
  rs = "rust",
  ts = "typescript",
  zig = "zig",
}

local language_extensions = {
  c = ".c",
  cpp = ".cpp",
  go = ".go",
  javascript = ".js",
  javascriptreact = ".jsx",
  lua = ".lua",
  bash = ".sh",
  python = ".py",
  rust = ".rs",
  sh = ".sh",
  typescript = ".ts",
  typescriptreact = ".tsx",
  zsh = ".sh",
  zig = ".zig",
}

local path_extensions = {
  c = true,
  cc = true,
  cpp = true,
  cts = true,
  cxx = true,
  go = true,
  h = true,
  hh = true,
  hpp = true,
  js = true,
  lua = true,
  mjs = true,
  mts = true,
  py = true,
  rs = true,
  ts = true,
  zig = true,
}

local function startswith(text, prefix)
  return type(text) == "string" and type(prefix) == "string" and text:sub(1, #prefix) == prefix
end

local function is_list(value)
  local checker = vim.islist or vim.tbl_islist
  return type(value) == "table" and checker(value)
end

local function deepcopy(value)
  return vim.deepcopy(value)
end

function M.is_list(value)
  return is_list(value)
end

function M.deepcopy(value)
  return deepcopy(value)
end

function M.merge(base, overrides)
  if overrides == nil then
    return deepcopy(base)
  end

  if type(base) ~= "table" or type(overrides) ~= "table" or is_list(base) or is_list(overrides) then
    return deepcopy(overrides)
  end

  local merged = deepcopy(base)

  for key, value in pairs(overrides) do
    if type(merged[key]) == "table" and type(value) == "table" and not is_list(merged[key]) and not is_list(value) then
      merged[key] = M.merge(merged[key], value)
    else
      merged[key] = deepcopy(value)
    end
  end

  return merged
end

local function path_sep()
  return package.config:sub(1, 1)
end

function M.joinpath(...)
  if vim.fs and vim.fs.joinpath then
    return vim.fs.joinpath(...)
  end

  local parts = { ... }
  local sep = path_sep()
  local joined = ""

  for _, part in ipairs(parts) do
    if part and part ~= "" then
      if joined == "" then
        joined = part
      else
        if joined:sub(-1) ~= sep then
          joined = joined .. sep
        end

        if part:sub(1, 1) == sep then
          part = part:sub(2)
        end

        joined = joined .. part
      end
    end
  end

  return joined
end

function M.dirname(path)
  if not path or path == "" then
    return ""
  end

  if vim.fs and vim.fs.dirname then
    return vim.fs.dirname(path)
  end

  return path:match("^(.*)[/\\][^/\\]+$") or ""
end

function M.basename(path)
  if not path or path == "" then
    return ""
  end

  return path:match("([^/\\]+)$") or path
end

function M.stem_and_extension(path)
  local basename = M.basename(path)
  local stem, extension = basename:match("^(.*)(%.[^.]*)$")
  if not stem then
    return basename, ""
  end
  return stem, extension
end

function M.normalize_path(path)
  if not path or path == "" then
    return path
  end

  if vim.fs and vim.fs.normalize then
    return vim.fs.normalize(path)
  end

  return path
end

function M.is_absolute(path)
  if not path or path == "" then
    return false
  end

  if path_sep() == "\\" then
    return path:match("^%a:[/\\]") ~= nil or path:sub(1, 2) == "\\\\"
  end

  return path:sub(1, 1) == "/"
end

function M.resolve_path(path, cwd)
  if not path or path == "" then
    return path
  end

  if M.is_absolute(path) then
    return M.normalize_path(path)
  end

  if cwd and cwd ~= "" then
    return M.normalize_path(M.joinpath(cwd, path))
  end

  return M.normalize_path(path)
end

function M.relpath(base, target)
  if not base or not target then
    return nil
  end

  if vim.fs and vim.fs.relpath then
    return vim.fs.relpath(base, target)
  end

  base = M.normalize_path(base)
  target = M.normalize_path(target)

  if startswith(target, base .. "/") then
    return target:sub(#base + 2)
  end

  if target == base then
    return "."
  end

  return nil
end

function M.same_path(left, right)
  if not left or not right then
    return false
  end

  return M.normalize_path(left) == M.normalize_path(right)
end

function M.detect_language(bufnr)
  local filetype = vim.bo[bufnr].filetype
  if ft_map[filetype] then
    return ft_map[filetype]
  end

  local path = vim.api.nvim_buf_get_name(bufnr)
  local extension = path:match("%.([^./\\]+)$")
  if extension and ext_map[extension] then
    return ext_map[extension]
  end

  return nil
end

function M.get_extension(path)
  if not path or path == "" then
    return nil
  end

  return path:match("%.([^./\\]+)$")
end

function M.language_extension(language)
  return language_extensions[language] or ".txt"
end

function M.looks_like_path(path)
  if not path or path == "" or path == "[C]" or path:match("^node:") then
    return false
  end

  if path:find("/") or path:find("\\") or path:sub(1, 1) == "." then
    return true
  end

  local extension = path:match("%.([^./\\]+)$")
  return extension ~= nil and path_extensions[extension] == true
end

function M.is_user_path(path)
  if not path or path == "" then
    return false
  end

  if path:match("^/usr/") or path:match("^/nix/store/") or path:match("^/rustc/") or path:match("^node:") then
    return false
  end

  return true
end

function M.get_buffer_path(bufnr)
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == "" then
    return nil
  end
  return M.normalize_path(path)
end

function M.find_up(names, start)
  if not start or start == "" then
    return nil
  end

  if vim.fs and vim.fs.find then
    return vim.fs.find(names, {
      path = start,
      upward = true,
    })[1]
  end

  return nil
end

function M.find_project_venv_python(start)
  local venv = M.find_up(".venv", start)
  if not venv then
    return nil
  end

  local python = M.joinpath(venv, "bin", "python")
  if vim.fn.executable(python) == 1 then
    return M.normalize_path(python)
  end

  local python3 = M.joinpath(venv, "bin", "python3")
  if vim.fn.executable(python3) == 1 then
    return M.normalize_path(python3)
  end

  return nil
end

local function resolve_python_command(vars)
  local source_file = vars.source_file or vars.file
  local start = M.dirname(source_file)
  return M.find_project_venv_python(start) or "python3"
end

function M.default_python_argv(vars)
  return { resolve_python_command(vars), vars.file }
end

function M.default_python_module_argv(vars)
  local source_file = vars.source_file or vars.file
  local start = M.dirname(source_file)
  local python = resolve_python_command(vars)

  if vars.is_temp_source then
    return { python, vars.file }
  end

  local git_dir = M.find_up(".git", start)
  local run_root = git_dir and M.dirname(git_dir) or vars.cwd or start
  local rel = M.relpath(run_root, source_file)

  if rel and rel:sub(-3) == ".py" then
    local module = rel:gsub("%.py$", ""):gsub("[/\\]", ".")
    module = module:gsub("%.__init__$", "")
    if module ~= "" and not module:find("[^%w_%.]") then
      return { python, "-m", module }
    end
  end

  return { python, vars.file }
end

function M.get_buffer_text(bufnr, start_line, end_line)
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  local text = table.concat(lines, "\n")

  if #lines > 0 then
    text = text .. "\n"
  end

  return text
end

function M.write_file(path, content)
  local file, err = io.open(path, "w")
  if not file then
    return nil, err
  end

  file:write(content)
  file:close()
  return true
end

function M.unlink(path)
  if not path or path == "" then
    return
  end

  if uv and uv.fs_unlink then
    pcall(uv.fs_unlink, path)
    return
  end

  os.remove(path)
end

function M.make_temp_source_path(original_path, language)
  local token = tostring((uv and uv.hrtime and uv.hrtime()) or os.time())
  local extension = M.language_extension(language)

  if original_path and original_path ~= "" then
    local directory = M.dirname(original_path)
    local stem = M.stem_and_extension(original_path)
    local safe_stem = tostring(stem):gsub("[^%w%-_]+", "_")
    return M.normalize_path(M.joinpath(directory, "." .. safe_stem .. ".bug-chaser." .. token .. extension))
  end

  return M.normalize_path(vim.fn.tempname() .. extension)
end

function M.make_temp_target_path(original_path)
  local token = tostring((uv and uv.hrtime and uv.hrtime()) or os.time())
  local suffix = path_sep() == "\\" and ".exe" or ""

  if original_path and original_path ~= "" then
    local directory = M.dirname(original_path)
    return M.normalize_path(M.joinpath(directory, ".bug-chaser.bin." .. token .. suffix))
  end

  return M.normalize_path(vim.fn.tempname() .. suffix)
end

function M.expand_string(value, vars)
  return (value:gsub("%$([%w_]+)", function(key)
    local replacement = vars[key]
    if replacement == nil then
      return "$" .. key
    end
    return tostring(replacement)
  end))
end

function M.expand_argv(command, args, vars)
  local argv = {}
  local resolved_command = command
  local resolved_args = args

  if type(resolved_command) == "function" then
    resolved_command = resolved_command(vim.deepcopy(vars))
  end

  if type(resolved_args) == "function" then
    resolved_args = resolved_args(vim.deepcopy(vars))
  end

  local function push(part)
    if part == nil or part == "" then
      return
    end
    table.insert(argv, M.expand_string(tostring(part), vars))
  end

  if type(resolved_command) == "table" then
    for _, part in ipairs(resolved_command) do
      push(part)
    end
  else
    push(resolved_command)
  end

  if type(resolved_args) == "table" then
    for _, arg in ipairs(resolved_args) do
      push(arg)
    end
  else
    push(resolved_args)
  end

  return argv
end

function M.combine_output(stdout, stderr)
  local chunks = {}

  if stderr and stderr ~= "" then
    table.insert(chunks, stderr)
  end

  if stdout and stdout ~= "" then
    table.insert(chunks, stdout)
  end

  return table.concat(chunks, "\n")
end

function M.strip_ansi(text)
  if not text or text == "" then
    return ""
  end

  local cleaned = text
  cleaned = cleaned:gsub("\27%[[0-9;?]*[%a]", "")
  cleaned = cleaned:gsub("\27%][^\7]*\7", "")
  cleaned = cleaned:gsub("\r", "")

  return cleaned
end

function M.truncate(text, limit)
  if not text then
    return ""
  end

  if #text <= limit then
    return text
  end

  return text:sub(1, limit - 3) .. "..."
end

return M
