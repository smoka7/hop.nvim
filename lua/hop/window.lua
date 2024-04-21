-- Provide windows and lines to jump where you want
---@alias WindowRow integer 1-based line row at window
---@alias WindowCol integer 0-based column at window, also as string byte index
---@alias WindowCell integer 0-based displayed cell column at window; often computed via `strdisplaywidth()`
---@alias WindowChar integer 0-based character index at string
-- For multi-byte character, there may be WindowCol ~= WindowCell ~= WindowChar like below showed
-- LineString:   a #### b     => '##' is a 4-bytes character takes 2-cells
-- WindowCol     0 1234 5
-- WindowCell:   0 1 2  3
-- WindowChar:   0 1    2
--
-- Infos for some neovim api:
-- * 1-based line, 0-based column: nvim_win_get_cursor, nvim_win_set_cursor
-- * 0-based line, end-exclusive: nvim_buf_get_lines
-- * 0-based line, end-inclusive; 0-based column, end-exclusive: nvim_buf_set_extmark
-- * 1-based line: foldclosedend
-- * 0-based character index: charidx, strcharpart
-- * 0-based byte index: byteidx, strpart

---@class CursorPos
---@field row WindowRow
---@field col WindowCol

---@alias LineRange WindowRow[] Line range with [top-inclusive, bottom-inclusive]
---@alias ColumnRange WindowCol[] Column range with [left-inclusive, right-exclusive)

---@class LineContext
---@field row WindowRow
---@field line string
---@field col_bias WindowCol Bias column of the left clipped line

---@class WindowContext
---@field win_handle integer
---@field buf_handle integer
---@field cursor CursorPos
---@field line_range LineRange
---@field column_range ColumnRange Left-column for top-line and right-column for bottom-line
---@field win_width WindowCell Window cell width excluding fold, sign and number columns
---@field col_offset WindowCell First cell column displayed (also is the cell number hidden to window left)
---@field col_first WindowCell Cursor cell column relative to the first cell column displayed

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

-- Convert CursorPos to extmark position
---@param pos CursorPos
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

  local line_width = vim.fn.strdisplaywidth(line)
  local line_chars = vim.fn.strchars(line)
  -- No multi-byte character
  if line_width == line_chars then
    return cell
  end
  -- Line is shorter than cell, all line should include
  if line_width <= cell then
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
  return i
end

-- Get information about the window and the cursor
---@param win_handle number
---@param buf_handle number
---@return WindowContext
local function window_context(win_handle, buf_handle)
  local win_info = vim.fn.getwininfo(win_handle)[1]
  local win_view = api.nvim_win_call(win_handle, vim.fn.winsaveview)
  local cursor_pos = api.nvim_win_get_cursor(win_handle)
  local cursor = { row = cursor_pos[1], col = cursor_pos[2] }

  local bottom_line = api.nvim_buf_get_lines(buf_handle, win_info.botline - 1, win_info.botline, false)[1]
  local right_column = string.len(bottom_line)

  local win_width = nil
  if not vim.wo.wrap then
    --number of columns occupied by any	'foldcolumn', 'signcolumn' and line number in front of the text
    win_width = win_info.width - win_info.textoff
  end

  local cursor_line = api.nvim_buf_get_lines(buf_handle, cursor.row - 1, cursor.row, false)[1]
  local col_first = vim.fn.strdisplaywidth(cursor_line:sub(1, cursor.col)) - win_view.leftcol

  return {
    win_handle = win_handle,
    buf_handle = buf_handle,
    cursor = cursor,
    line_range = { win_info.topline, win_info.botline },
    column_range = { 0, right_column },
    win_width = win_width,
    col_offset = win_view.leftcol,
    col_first = col_first,
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
  for _, w in ipairs(opts.windows_list()) do
    local valid_win = api.nvim_win_is_valid(w)
    local focusable_win = vim.api.nvim_win_get_config(w).focusable
    if valid_win and focusable_win and w ~= cur_hwin then
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
      col_bias = 0,
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

  if opts.current_line_only then
    win_ctx.line_range[1] = row
    win_ctx.line_range[2] = row
    win_ctx.column_range[1] = 0
    win_ctx.column_range[2] = string.len(line)
  end

  if opts.direction == hint.HintDirection.BEFORE_CURSOR then
    win_ctx.line_range[2] = win_ctx.cursor.row
    win_ctx.column_range[2] = win_ctx.cursor.col

    -- For non-empty lines we have to increment it so we include the cursor
    if #line > 0 then
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
  local end_cell = vim.fn.strdisplaywidth(line_ctx.line)
  if win_ctx.win_width ~= nil then
    end_cell = win_ctx.col_offset + win_ctx.win_width
  end

  -- Handle shifted_line with cell2char for multiple-bytes chars
  ---@type WindowChar
  local left_idx = M.cell2char(line_ctx.line, win_ctx.col_offset)
  ---@type WindowChar
  local right_idx = M.cell2char(line_ctx.line, end_cell)
  local shifted_line = vim.fn.strcharpart(line_ctx.line, left_idx, right_idx - left_idx)
  ---@type WindowCol
  local col_bias = vim.fn.byteidx(line_ctx.line, left_idx)

  if line_ctx.row == win_ctx.cursor.row then
    if opts.direction == hint.HintDirection.AFTER_CURSOR then
      shifted_line = shifted_line:sub(1 + win_ctx.cursor.col - col_bias)
      col_bias = win_ctx.cursor.col
    elseif opts.direction == hint.HintDirection.BEFORE_CURSOR then
      shifted_line = shifted_line:sub(1, 1 + win_ctx.cursor.col - col_bias)
    end
  end

  line_ctx.line = shifted_line
  line_ctx.col_bias = col_bias
end

return M
