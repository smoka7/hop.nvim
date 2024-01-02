-- Match jump target and return jump range within line
---@class Regex
---@field oneshot boolean
---@field match fun(s:string, jctx:JumpContext, opts:Options):MatchResult|nil

---@class MatchResult
---@field b WindowCol The begin column of matched string
---@field e WindowCol The end column of matched string
---@field off WindowCell Always zero, unless 'virtualedit' is enabled so we can jump to blank cell
---@field virt WindowCell|nil Always nil, unless 'virtualedit' is enabled so we can place hint at blank cell

---@class RegexModule
local M = {}

local hint = require('hop.hint')
local window = require('hop.window')
local mappings = require('hop.mappings')

-- Create MatchResult conveniently from vim.regex:match_str
---@return MatchResult|nil
function M.match_result(b, e, f, v)
  if b and e then
    return {
      b = b,
      e = e,
      off = f or 0,
      virt = v,
    }
  end
end

-- Regex modes for the buffer-driven generator.
---@param s string
---@return boolean
local function starts_with_uppercase(s)
  if #s == 0 then
    return false
  end

  local f = s:sub(1, vim.fn.byteidx(s, 1))
  -- if it’s a space, we assume it’s not uppercase, even though Lua doesn’t agree with us; I mean, Lua is horrible, who
  -- would like to argue with that creature, right?
  if f == ' ' then
    return false
  end

  return f:upper() == f
end

-- Regex by searching a pattern.
---@param pat string
---@param plain_search boolean|nil
---@return Regex
local function regex_by_searching(pat, plain_search)
  if plain_search then
    pat = vim.fn.escape(pat, '\\/.$^~[]')
  end

  local regex = vim.regex(pat)

  return {
    oneshot = false,
    match = function(s)
      return M.match_result(regex:match_str(s))
    end,
  }
end

-- Wrapper over M.regex_by_searching to add support for case sensitivity.
---@param pat string
---@param plain_search boolean
---@param opts Options
---@return Regex
function M.regex_by_case_searching(pat, plain_search, opts)
  local pat_case = ''
  if vim.o.smartcase then
    if not starts_with_uppercase(pat) then
      pat_case = '\\c'
    end
  elseif opts.case_insensitive then
    pat_case = '\\c'
  end
  local pat_mappings = mappings.checkout(pat, opts)

  if plain_search then
    pat = vim.fn.escape(pat, '\\/.$^~[]')
  end
  if pat_mappings ~= '' then
    pat = string.format([[\(%s\)\|\(%s\)]], pat, pat_mappings)
  end
  pat = pat .. pat_case

  local regex = vim.regex(pat)

  return {
    oneshot = false,
    match = function(s)
      return M.match_result(regex:match_str(s))
    end,
  }
end

-- Word regex.
---@return Regex
function M.regex_by_word_start()
  return regex_by_searching('\\k\\+')
end

-- Camel case regex.
---@return Regex
function M.regex_by_camel_case()
  local camel = '\\u\\l\\+'
  local acronyms = '\\u\\+\\ze\\u\\l'
  local upper = '\\u\\+'
  local lower = '\\l\\+'
  local rgb = '#\\x\\+\\>'
  local ox = '\\<0[xX]\\x\\+\\>'
  local oo = '\\<0[oO][0-7]\\+\\>'
  local ob = '\\<0[bB][01]\\+\\>'
  local num = '\\d\\+'

  local tab = { camel, acronyms, upper, lower, rgb, ox, oo, ob, num, '\\~', '!', '@', '#', '$' }
  -- regex that matches camel or acronyms or upper ... or num ...
  local patStr = '\\%(\\%(' .. table.concat(tab, '\\)\\|\\%(') .. '\\)\\)'

  local pat = vim.regex(patStr)
  return {
    oneshot = false,
    match = function(s)
      return M.match_result(pat:match_str(s))
    end,
  }
end

-- Line regex.
---@return Regex
function M.by_line_start()
  return {
    oneshot = true,
    ---@param jctx JumpContext
    match = function(_, jctx)
      local lctx = jctx.line_ctx
      local wctx = jctx.win_ctx
      if window.is_active_line(wctx, lctx) then
        return
      end
      if wctx.virtualedit and lctx.off_bias > 0 then
        local line_len = string.len(lctx.line) - lctx.col_bias
        return M.match_result(line_len, line_len + 1, lctx.off_bias, 0)
      else
        return M.match_result(0, 1)
      end
    end,
  }
end

-- Line regex at cursor position.
---@return Regex
function M.regex_by_vertical()
  return {
    oneshot = true,
    ---@param jctx JumpContext
    match = function(s, jctx, opts)
      local lctx = jctx.line_ctx
      local wctx = jctx.win_ctx
      if window.is_active_line(wctx, lctx) then
        return
      end

      local virt = wctx.virtualedit and wctx.cursor.virt or nil
      local line_cells = vim.fn.strdisplaywidth(lctx.line)
      local cursor_cells = wctx.win_offset + wctx.cursor.virt
      if cursor_cells > line_cells then
        local line_len = string.len(lctx.line) - lctx.col_bias
        if not virt then
          -- When virtualedit is enabled, the line EOL is taken as the last line cell that can jump to,
          -- so minus one to take the last line character as the last line cell when virtualedit is disabled.
          line_len = line_len - 1
        end
        return M.match_result(line_len, line_len + 1, cursor_cells - line_cells, virt)
      else
        if window.is_cursor_line(wctx, lctx) and opts.direction == hint.HintDirection.AFTER_CURSOR then
          return M.match_result(0, 1, 0, virt)
        else
          local idx = window.cell2char(s, wctx.cursor.virt)
          local col = vim.fn.byteidx(s, idx)
          return M.match_result(col, col + 1, 0, virt)
        end
      end
    end,
  }
end

-- Line regex skipping finding the first non-whitespace character on each line.
---@return Regex
function M.regex_by_line_start_skip_whitespace()
  local regex = vim.regex('\\S')

  return {
    oneshot = true,
    ---@param jctx JumpContext
    match = function(s, jctx)
      if window.is_active_line(jctx.win_ctx, jctx.line_ctx) then
        return
      end
      return M.match_result(regex:match_str(s))
    end,
  }
end

-- Anywhere regex.
---@return Regex
function M.regex_by_anywhere()
  return regex_by_searching('\\v(<.|^$)|(.>|^$)|(\\l)\\zs(\\u)|(_\\zs.)|(#\\zs.)')
end

return M
