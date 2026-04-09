local cwd = vim.fn.getcwd()
package.path = table.concat({
  cwd .. "/lua/?.lua",
  cwd .. "/lua/?/init.lua",
  package.path,
}, ";")

local bug_chaser = require("bug_chaser")
local config = require("bug_chaser.config")
local parser = require("bug_chaser.parser")
local ui = require("bug_chaser.ui")

local failures = {}

local function fail(message)
  table.insert(failures, message)
end

local function expect(condition, message)
  if not condition then
    fail(message)
  end
end

local function expect_equal(actual, expected, message)
  if actual ~= expected then
    fail(string.format("%s (expected %s, got %s)", message, vim.inspect(expected), vim.inspect(actual)))
  end
end

local function count_terminal_buffers()
  local count = 0

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buftype == "terminal" then
      count = count + 1
    end
  end

  return count
end

local function find_terminal_window()
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local bufnr = vim.api.nvim_win_get_buf(winid)
    if vim.bo[bufnr].buftype == "terminal" then
      return winid, bufnr
    end
  end
end

local function check_frame(name, language, output, context, expected_path_suffix, expected_lnum)
  local parsed = parser.parse(language, output, context)
  expect(parsed.selected_frame ~= nil, name .. ": expected a selected frame")
  if not parsed.selected_frame then
    return
  end

  expect(parsed.selected_frame.path ~= nil, name .. ": expected a frame path")
  if parsed.selected_frame.path then
    expect(parsed.selected_frame.path:sub(-#expected_path_suffix) == expected_path_suffix, name .. ": unexpected frame path")
  end

  expect_equal(parsed.selected_frame.lnum, expected_lnum, name .. ": unexpected line number")
end

check_frame(
  "python traceback",
  "python",
  [[Traceback (most recent call last):
  File "/tmp/project/app.py", line 4, in <module>
    main()
  File "/tmp/project/app.py", line 8, in main
    raise ValueError("boom")
ValueError: boom]],
  { cwd = "/tmp/project" },
  "/tmp/project/app.py",
  8
)

check_frame(
  "python syntax error",
  "python",
  [[Traceback (most recent call last):
  File "/tmp/project/test_2.py", line 3, in <module>
    from test import test_function
  File "/tmp/project/test.py", line 5
    print('Argument 1: ', arg_1
         ^
SyntaxError: '(' was never closed]],
  { cwd = "/tmp/project" },
  "/tmp/project/test.py",
  5
)

check_frame(
  "lua traceback",
  "lua",
  [[lua: /tmp/project/init.lua:6: attempt to call a nil value
stack traceback:
        /tmp/project/init.lua:6: in function 'main'
        /tmp/project/init.lua:10: in main chunk]],
  { cwd = "/tmp/project" },
  "/tmp/project/init.lua",
  6
)

check_frame(
  "javascript stack",
  "javascript",
  [[TypeError: boom
    at run (/tmp/project/index.js:12:5)
    at Object.<anonymous> (/tmp/project/index.js:18:1)]],
  { cwd = "/tmp/project" },
  "/tmp/project/index.js",
  12
)

check_frame(
  "javascript syntax error",
  "javascript",
  [[/tmp/project/index.js:7
console.log("oops"
                 ^
SyntaxError: missing ) after argument list]],
  { cwd = "/tmp/project" },
  "/tmp/project/index.js",
  7
)

check_frame(
  "c compile error",
  "c",
  [[/tmp/project/main.c:9:3: error: expected ';' before 'return']],
  { cwd = "/tmp/project" },
  "/tmp/project/main.c",
  9
)

check_frame(
  "go panic",
  "go",
  [[panic: boom

goroutine 1 [running]:
main.run()
        /tmp/project/main.go:11 +0x25
main.main()
        /tmp/project/main.go:15 +0xf]],
  { cwd = "/tmp/project" },
  "/tmp/project/main.go",
  11
)

check_frame(
  "rust panic",
  "rust",
  [[thread 'main' panicked at index out of bounds, src/main.rs:7:9
note: run with `RUST_BACKTRACE=1` environment variable to display a backtrace]],
  { cwd = "/tmp/project" },
  "/tmp/project/src/main.rs",
  7
)

check_frame(
  "rust compiler arrow",
  "rust",
  [[error: expected expression, found `let`
 --> src/main.rs:7:5
  |
7 |     let value =
  |     ^^^ expected expression]],
  { cwd = "/tmp/project" },
  "/tmp/project/src/main.rs",
  7
)

check_frame(
  "zig panic",
  "zig",
  [[thread 1234 panic: integer overflow
/tmp/project/main.zig:14:13: 0x103ce52 in main (main)]],
  { cwd = "/tmp/project" },
  "/tmp/project/main.zig",
  14
)

do
  local parsed = parser.parse("python", [[Traceback (most recent call last):
  File "/tmp/project/.app.bug-chaser.1.py", line 3, in <module>
    crash()
RuntimeError: boom]], {
    cwd = "/tmp/project",
    remap = {
      line_offset = 19,
      source_bufnr = 3,
      source_path = "/tmp/project/app.py",
      temp_path = "/tmp/project/.app.bug-chaser.1.py",
    },
    source_bufnr = 3,
    source_path = "/tmp/project/app.py",
  })

  expect(parsed.selected_frame ~= nil, "selection remap: expected a selected frame")
  if parsed.selected_frame then
    expect_equal(parsed.selected_frame.path, "/tmp/project/app.py", "selection remap: expected source path")
    expect_equal(parsed.selected_frame.lnum, 22, "selection remap: expected mapped line")
    expect_equal(parsed.selected_frame.source_bufnr, 3, "selection remap: expected source buffer")
  end
end

do
  local resolved = config.resolve({
    languages = {
      c = {
        compile_args = { "$file", "-o", "$target" },
      },
    },
  })

  expect_equal(#resolved.languages.c.compile_args, 3, "config merge: expected compile args to be replaced")
  expect_equal(resolved.languages.c.compile_args[1], "$file", "config merge: unexpected first arg")
  expect_equal(resolved.languages.c.compile_args[2], "-o", "config merge: unexpected second arg")
  expect_equal(resolved.languages.c.compile_args[3], "$target", "config merge: unexpected third arg")
end

do
  local resolved = config.resolve(true)
  expect(type(resolved) == "table", "config resolve: expected a table when given a non-table value")
  expect(type(resolved.languages) == "table", "config resolve: expected default languages when given a non-table value")
  expect(type(resolved.terminal) == "table", "config resolve: expected default terminal config when given a non-table value")
end

do
  vim.cmd("enew")

  local bufnr = vim.api.nvim_get_current_buf()
  local winid = vim.api.nvim_get_current_win()

  vim.bo[bufnr].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "print('hello')" })
  vim.api.nvim_win_set_width(winid, 40)

  ui.show({
    col = 1,
    lnum = 1,
    source_bufnr = bufnr,
  }, "boom", {
    open_command = "split",
    virtual_line = {
      above = true,
      highlight = "ErrorMsg",
      prefix = " ",
    },
  }, {
    winid = winid,
  })

  local marks = vim.api.nvim_buf_get_extmarks(bufnr, -1, 0, -1, { details = true })
  expect(#marks > 0, "ui virtual line: expected an extmark to be created")

  if #marks > 0 then
    local virt_lines = marks[#marks][4].virt_lines
    expect(type(virt_lines) == "table", "ui virtual line: expected virt_lines details")

    if type(virt_lines) == "table" then
      local chunks = virt_lines[1]
      expect(type(chunks) == "table" and #chunks >= 2, "ui virtual line: expected text and padding chunks")

      if type(chunks) == "table" and #chunks >= 2 then
        expect_equal(chunks[1][1], " boom", "ui virtual line: unexpected text chunk")
        expect_equal(chunks[2][2], "ErrorMsg", "ui virtual line: unexpected padding highlight")
        expect(vim.fn.strdisplaywidth(chunks[2][1]) > 0, "ui virtual line: expected padding to extend the background")
      end
    end
  end

  pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
end

do
  local temp_path = vim.fn.tempname() .. ".py"
  vim.o.shell = "sh"
  vim.o.swapfile = false
  vim.fn.writefile({
    "print('one')",
    "print('two')",
    "print('three')",
  }, temp_path)

  local function configure_for_line(line_number, message)
    bug_chaser.setup({
      terminal = {
        focus = false,
        height = 8,
      },
      languages = {
        python = {
          args = {
            "-c",
            string.format("printf '%%s\\n' \"$file:%d: %s\"; exit 1", line_number, message),
          },
          command = "/bin/sh",
          mode = "command",
        },
      },
    })
  end

  vim.cmd("edit " .. vim.fn.fnameescape(temp_path))

  local source_bufnr = vim.api.nvim_get_current_buf()
  local source_winid = vim.api.nvim_get_current_win()

  configure_for_line(3, "first failure")
  bug_chaser.run_command({ range = 0 })

  local first_run_ok = vim.wait(3000, function()
    return vim.api.nvim_win_is_valid(source_winid) and vim.api.nvim_win_get_cursor(source_winid)[1] == 3
  end, 20)

  expect(first_run_ok, "terminal integration: expected first run to jump to line 3")
  expect_equal(vim.api.nvim_get_current_win(), source_winid, "terminal integration: expected focus to stay in the source window")
  expect_equal(count_terminal_buffers(), 1, "terminal integration: expected one terminal buffer after first run")

  local terminal_winid_1 = find_terminal_window()
  expect(terminal_winid_1 ~= nil, "terminal integration: expected a terminal window after first run")

  configure_for_line(2, "second failure")
  bug_chaser.run_command({ range = 0 })

  local second_run_ok = vim.wait(3000, function()
    return vim.api.nvim_win_is_valid(source_winid) and vim.api.nvim_win_get_cursor(source_winid)[1] == 2
  end, 20)

  expect(second_run_ok, "terminal integration: expected second run to jump to line 2")
  expect_equal(vim.api.nvim_get_current_win(), source_winid, "terminal integration: expected focus to stay in the source window after reuse")
  expect_equal(count_terminal_buffers(), 1, "terminal integration: expected the dedicated terminal buffer to be reused")

  local terminal_winid_2 = find_terminal_window()
  expect_equal(terminal_winid_2, terminal_winid_1, "terminal integration: expected the dedicated terminal window to be reused")

  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if winid ~= source_winid and vim.api.nvim_win_is_valid(winid) then
      pcall(vim.api.nvim_win_close, winid, true)
    end
  end

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buftype == "terminal" then
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end
  end

  pcall(vim.api.nvim_buf_delete, source_bufnr, { force = true })
  vim.fn.delete(temp_path)
end

if #failures > 0 then
  error(table.concat(failures, "\n"))
end

print("bug-chaser tests passed")
