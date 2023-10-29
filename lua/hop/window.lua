local hint = require('hop.hint')

---@class WindowContext
---@field hwin number
---@field cursor_pos number[]
---@field top_line number
---@field bot_line number
---@field fcol number
---@field win_width number
---@field col_offset number

---@class Context
---@field buffer_handle number
---@field contexts WindowContext[]

---@class LineContext
---@field line_nr number
---@field line string

local M = {}

-- get information about the window and the cursor
---@param win_handle number
---@return WindowContext
local function window_context(win_handle, buf_handle)
  vim.api.nvim_set_current_win(win_handle)
  local win_info = vim.fn.getwininfo(win_handle)[1]
  local win_view = vim.fn.winsaveview()
  local cursor_pos = vim.api.nvim_win_get_cursor(win_handle)

  local win_width = nil
  if not vim.wo.wrap then
    win_width = win_info.width - win_info.textoff
  end
  local cursor_line = vim.api.nvim_buf_get_lines(buf_handle, cursor_pos[1] - 1, cursor_pos[1], false)[1]
  local fcol = vim.fn.strdisplaywidth(cursor_line:sub(1, cursor_pos[2])) - win_view.leftcol

  return {
    hwin = win_handle,
    cursor_pos = cursor_pos,
    top_line = win_info.topline - 1,
    bot_line = win_info.botline,
    win_width = win_width,
    fcol = fcol,
    col_offset = win_view.leftcol,
  }
end

-- returns current window context or all visible windows context in multiwindow mode
---@param opts Options
---@return Context[]
function M.get_window_context(opts)
  ---@type Context[]
  local contexts = {}

  -- Generate contexts of windows
  local cur_hwin = vim.api.nvim_get_current_win()
  local cur_hbuf = vim.api.nvim_win_get_buf(cur_hwin)

  contexts[1] = {
    buffer_handle = cur_hbuf,
    contexts = { window_context(cur_hwin, cur_hbuf) },
  }

  if not opts.multi_windows then
    return contexts
  end

  -- Get the context for all the windows in current tab
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(w) and vim.api.nvim_win_get_config(w).relative == '' then
      local b = vim.api.nvim_win_get_buf(w)

      -- skips current window and excluded filetypes
      if not (w == cur_hwin or vim.tbl_contains(opts.excluded_filetypes, vim.bo[b].filetype)) then
        contexts[#contexts + 1] = {
          buffer_handle = b,
          contexts = { window_context(w, b) },
        }
      end
    end
  end

  return contexts
end

-- Collect visible and unfold lines of window context
---@param buf_handle number
---@param context WindowContext
---@return LineContext[]
function M.get_lines_context(buf_handle, context)
  ---@type LineContext[]
  local lines = {}

  local lnr = context.top_line
  while lnr < context.bot_line do -- top_line is inclusive and bot_line is exclusive
    local fold_end = vim.api.nvim_win_call(context.hwin, function()
      return vim.fn.foldclosedend(lnr + 1) -- `foldclosedend()` use 1-based line number
    end)
    if fold_end == -1 then -- line isn't folded
      lines[#lines + 1] = {
        line_nr = lnr,
        line = vim.api.nvim_buf_get_lines(buf_handle, lnr, lnr + 1, false)[1], -- `nvim_buf_get_lines()` uses 0-based line index
      }
      lnr = lnr + 1
    else
      lnr = fold_end -- skip folded lines
    end
  end

  return lines
end

-- Clip the window context based on the direction.
---@param context WindowContext
---@param direction HintDirection
function M.clip_window_context(context, direction)
  -- everything after the cursor will be clipped.
  if direction == hint.HintDirection.BEFORE_CURSOR then
    context.bot_line = context.cursor_pos[1]
    -- everything before the cursor will be clipped.
  elseif direction == hint.HintDirection.AFTER_CURSOR then
    context.top_line = context.cursor_pos[1] - 1
  end
end

return M
