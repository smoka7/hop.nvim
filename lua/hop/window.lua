-- Provide windows and lines to jump where you want
---@alias WindowRow integer 1-based line row at window
---@alias WindowCol integer 0-based column at window, also as string byte index
---@alias WindowCell integer 0-based displayed cell column at window; often computed via `strdisplaywidth()`
---@alias WindowChar integer 0-based character index at string
-- For multi-byte character, there may be WindowCol ~= WindowCell ~= WindowChar like below showed
-- ```
-- LineString:   a #### b     => '####' is a 4-bytes character takes 2-cells
-- WindowCol:    0 1234 5
-- WindowCell:   0 1 2  3
-- WindowChar:   0 1    2
-- ```
--
-- Infos for some neovim api:
-- * 1-based line, 0-based column: nvim_win_get_cursor(), nvim_win_set_cursor()
-- * 1-based line, 1-based column: getcurpos(), setpos()
-- * 0-based line, end-exclusive: nvim_buf_get_lines()
-- * 0-based line, end-inclusive; 0-based column, end-exclusive: nvim_buf_set_extmark()
-- * 1-based line: foldclosedend()
-- * 0-based character index: charidx(), strcharpart()
-- * 0-based byte index: byteidx(), strpart()

---@class Cursor Cursor position and display information
---@field row WindowRow
---@field col WindowCol
---@field off WindowCell Jump to blank cell when 'virtualedit' is enabled
---@field virt WindowCell|nil The cursor cell column displayed relative to the WindowContext.win_offset

---@alias LineRange WindowRow[] Line range with [top-inclusive, bottom-inclusive]
---@alias ColumnRange WindowCol[] Column range with [left-inclusive, right-exclusive)

---@class LineContext
---@field row WindowRow
---@field line string
---@field line_cliped string
---@field col_bias WindowCol Bias column of the left clipped line
---@field off_bias WindowCol Bias cell column of the left clipped blank cells for 'virtualedit' is enabled

-- The Cursor and LineContext under WindowContext:
-- ```
--                  | virt         |
-- | col_bias       |        | off |
-- 1****************|========~~~~~~$~~|
-- | win_offset     | win_width       |
--
--       | off                     |
-- 2*****|~~~~~~~~~~|~~~~~~~~~~~~~~$~~|
--       | off_bias | win_width       |
-- ```
-- '1' : line 1 with long line string
-- '2' : line 2 with short line string
-- '*' : line string hidded to window left
-- '=' : line string displayed on window
-- '~' : blank cells with any text after line string
-- '$' : cursor with 'virtualedit' enabled
--
---@class WindowContext
---@field win_handle integer
---@field buf_handle integer
---@field cursor Cursor
---@field line_range LineRange
---@field column_range ColumnRange Left-column for top-line and right-column for bottom-line
---@field win_width WindowCell Window cell width excluding fold, sign and number columns
---@field win_offset WindowCell First cell column displayed at window (also is the cell number hidden to window left)
---@field virtualedit boolean The 'virtualedit' is enabled or not

local M = {}
local api = vim.api

-- Convert WindowRow to extmark line
---@param row WindowRow
function M.row2extmark(row)
  return row - 1
end

-- Convert WindowCol to extmark column
---@param col WindowCol
function M.col2extmark(col)
  return col
end

-- Convert Cursor to extmark position
---@param pos Cursor
function M.pos2extmark(pos)
  return pos.row - 1, pos.col
end

-- Convert LineRange to start and end row for extmark
---@param range LineRange
function M.line_range2extmark(range)
  return range[1] - 1, range[2] - 1
end

-- Convert ColumnRange to start and end column for extmark
---@param range ColumnRange
function M.column_range2extmark(range)
  return range[1], range[2]
end

-- Get the character index at the window column
---@param line string
---@param cell WindowCell
---@return WindowChar
function M.cell2char(line, cell)
  if cell <= 0 then
    return 0
  end

  local line_cells = vim.fn.strdisplaywidth(line)
  local line_chars = vim.fn.strchars(line)
  -- No multi-byte character
  if line_cells == line_chars then
    return cell
  end
  -- Line is shorter than cell, all line should include
  if line_cells <= cell then
    return line_chars
  end

  local lst
  -- Line is very long
  if line_chars >= cell then
    -- Split the line to individual characters
    lst = vim.fn.split(vim.fn.strcharpart(line, 0, cell), '\\zs')
  else
    lst = vim.fn.split(line, '\\zs')
  end

  local i, w = 0, 0
  repeat
    i = i + 1
    w = w + vim.fn.strdisplaywidth(lst[i])
  until w >= cell
  -- If w < cell, that is the i-th multi-byte character is after the cell
  return w == cell and i or i - 1
end

-- Report virtualedit is enabled or not
---@return boolean
local function is_virtualedit_enabled(win_handle)
  local ve = vim.wo[win_handle].virtualedit
  local mode = vim.fn.mode()
  return (ve == 'all') or (ve == 'insert' and mode == 'i') or (ve == 'block' and mode == '\22')
end

-- Get information about the window and the cursor
---@param win_handle number
---@param buf_handle number
---@return WindowContext
local function window_context(win_handle, buf_handle)
  local win_info = vim.fn.getwininfo(win_handle)[1]
  local win_view = api.nvim_win_call(win_handle, vim.fn.winsaveview)
  local cursor_pos = vim.fn.getcurpos(win_handle)
  ---@type Cursor
  local cursor = {
    row = cursor_pos[2],
    col = cursor_pos[3] - 1,
    off = cursor_pos[4],
    virt = nil,
  }
  local cursor_line = api.nvim_buf_get_lines(buf_handle, cursor.row - 1, cursor.row, false)[1]
  cursor.virt = vim.fn.strdisplaywidth(cursor_line:sub(1, cursor.col)) + cursor.off - win_view.leftcol

  local bottom_line = api.nvim_buf_get_lines(buf_handle, win_info.botline - 1, win_info.botline, false)[1]
  local right_column = string.len(bottom_line)

  local win_width = nil
  if not vim.wo.wrap then
    -- Number of columns occupied by any 'foldcolumn', 'signcolumn' and line number in front of the text
    win_width = win_info.width - win_info.textoff
  end

  return {
    win_handle = win_handle,
    buf_handle = buf_handle,
    cursor = cursor,
    line_range = { win_info.topline, win_info.botline },
    column_range = { 0, right_column },
    win_width = win_width,
    win_offset = win_view.leftcol,
    virtualedit = is_virtualedit_enabled(win_handle),
  }
end

-- Get all windows context
---@param opts Options
---@return WindowContext[] The first is always current window
function M.get_windows_context(opts)
  ---@type WindowContext[]
  local contexts = {}

  -- Generate contexts of windows
  local cur_hwin = api.nvim_get_current_win()
  local cur_hbuf = api.nvim_win_get_buf(cur_hwin)

  contexts[1] = window_context(cur_hwin, cur_hbuf)

  if not opts.multi_windows then
    return contexts
  end

  -- Get the context for all the windows in current tab
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    local valid_win = api.nvim_win_is_valid(w)
    local not_relative = api.nvim_win_get_config(w).relative == ''
    if valid_win and not_relative and w ~= cur_hwin then
      local b = api.nvim_win_get_buf(w)

      -- Skips current window and excluded filetypes
      if not (vim.tbl_contains(opts.excluded_filetypes, vim.bo[b].filetype)) then
        contexts[#contexts + 1] = window_context(w, b)
      end
    end
  end

  return contexts
end

-- Collect visible and unfold lines of window context
---@param win_ctx WindowContext
---@return LineContext[]
function M.get_lines_context(win_ctx)
  ---@type LineContext[]
  local lines = {}

  local lnr = win_ctx.line_range[1]
  while lnr <= win_ctx.line_range[2] do
    local fold_end = api.nvim_win_call(win_ctx.win_handle, function()
      return vim.fn.foldclosedend(lnr)
    end)
    ---@type LineContext
    local line_ctx = {
      row = lnr,
      line = '',
      line_cliped = '',
      col_bias = 0,
      off_bias = 0,
    }
    if fold_end == -1 then
      line_ctx.line = api.nvim_buf_get_lines(win_ctx.buf_handle, lnr - 1, lnr, false)[1]
    else
      -- Skip folded lines
      -- Let line = '' to take the first folded line as an empty line, where only the first column can move to
      lnr = fold_end
    end
    lines[#lines + 1] = line_ctx
    lnr = lnr + 1
  end

  return lines
end

---@param win_ctx WindowContext
function M.is_active_window(win_ctx)
  return win_ctx.win_handle == vim.api.nvim_get_current_win()
end

---@param win_ctx WindowContext
---@param line_ctx LineContext
function M.is_cursor_line(win_ctx, line_ctx)
  return win_ctx.cursor.row == line_ctx.row
end

---@param win_ctx WindowContext
---@param line_ctx LineContext
function M.is_active_line(win_ctx, line_ctx)
  return win_ctx.win_handle == vim.api.nvim_get_current_win() and win_ctx.cursor.row == line_ctx.row
end

-- Clip the window context area
---@param win_ctx WindowContext
---@param opts Options
function M.clip_window_context(win_ctx, opts)
  local hint = require('hop.hint')

  local row = win_ctx.cursor.row
  local line = api.nvim_buf_get_lines(win_ctx.buf_handle, row - 1, row, false)[1]
  local line_len = string.len(line)

  if opts.current_line_only then
    win_ctx.line_range[1] = row
    win_ctx.line_range[2] = row
    win_ctx.column_range[1] = 0
    win_ctx.column_range[2] = line_len
  end

  if opts.direction == hint.HintDirection.BEFORE_CURSOR then
    win_ctx.line_range[2] = win_ctx.cursor.row
    win_ctx.column_range[2] = win_ctx.cursor.col

    -- For non-empty lines we have to increment it so we include the cursor
    if win_ctx.cursor.col + 1 <= line_len then
      win_ctx.column_range[2] = win_ctx.cursor.col + 1
    end
  elseif opts.direction == hint.HintDirection.AFTER_CURSOR then
    win_ctx.line_range[1] = win_ctx.cursor.row
    win_ctx.column_range[1] = win_ctx.cursor.col
  end
end

-- Clip line context within window
---@param line_ctx LineContext
---@param win_ctx WindowContext
---@param opts Options
function M.clip_line_context(win_ctx, line_ctx, opts)
  local hint = require('hop.hint')

  ---@type WindowCell
  local line_cells = vim.fn.strdisplaywidth(line_ctx.line)
  local end_cell = line_cells
  if win_ctx.win_width ~= nil then
    end_cell = win_ctx.win_offset + win_ctx.win_width
  end

  -- Handle cliped line with cell2char for multiple-bytes chars
  ---@type WindowChar
  local left_idx = M.cell2char(line_ctx.line, win_ctx.win_offset)
  ---@type WindowChar
  local right_idx = M.cell2char(line_ctx.line, end_cell)
  local line_cliped = vim.fn.strcharpart(line_ctx.line, left_idx, right_idx - left_idx)
  ---@type WindowCol
  local col_bias = vim.fn.byteidx(line_ctx.line, left_idx)

  if line_ctx.row == win_ctx.cursor.row then
    if opts.direction == hint.HintDirection.AFTER_CURSOR then
      line_cliped = line_cliped:sub(1 + win_ctx.cursor.col - col_bias)
      col_bias = win_ctx.cursor.col
    elseif opts.direction == hint.HintDirection.BEFORE_CURSOR then
      line_cliped = line_cliped:sub(1, 1 + win_ctx.cursor.col - col_bias)
    end
  end

  ---@type WindowCol
  local off_bias = 0
  if win_ctx.win_offset > line_cells then
    off_bias = win_ctx.win_offset - line_cells
  end

  line_ctx.line_cliped = line_cliped
  line_ctx.col_bias = col_bias
  line_ctx.off_bias = off_bias
end

return M
