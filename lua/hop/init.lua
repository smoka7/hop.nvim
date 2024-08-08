local api = vim.api
local M = {}

local K_Esc = api.nvim_replace_termcodes('<Esc>', true, false, true)
local K_BS = api.nvim_replace_termcodes('<BS>', true, false, true)
local K_C_H = api.nvim_replace_termcodes('<C-H>', true, false, true)
local K_CR = api.nvim_replace_termcodes('<CR>', true, false, true)
local K_NL = api.nvim_replace_termcodes('<NL>', true, false, true)

-- Ensure options are sound.
--
-- Some options cannot be used together. For instance, multi_windows and current_line_only don’t really make sense used
-- together. This function will notify the user of such ill-formed configurations.
---@param opts Options
local function check_opts(opts)
  if not opts then
    return
  end

  if vim.version.cmp({ 0, 10, 0 }, vim.version()) < 0 then
    local hint = require('hop.hint')
    opts.hint_type = hint.HintType.OVERLAY
  end

  if opts.multi_windows and opts.current_line_only then
    vim.notify('Cannot use current_line_only across multiple windows', vim.log.levels.WARN)
  end

  -- disable multi windows for visual mode
  local mode = api.nvim_get_mode().mode
  if mode ~= 'n' and mode ~= 'nt' then
    opts.multi_windows = false
  end
end

-- Allows to override global options with user local overrides.
---@param opts Options
---@return Options
local function override_opts(opts)
  check_opts(opts)
  return setmetatable(opts or {}, { __index = M.opts })
end

-- Display error messages.
---@param msg string
---@param teasing boolean
local function eprintln(msg, teasing)
  if teasing then
    api.nvim_echo({ { msg, 'Error' } }, true, {})
  end
end

---@param buf_list number[] list of buffer handles
---@param hl_ns number highlight namespace
local function clear_namespace(buf_list, hl_ns)
  for _, buf in ipairs(buf_list) do
    if api.nvim_buf_is_valid(buf) then
      api.nvim_buf_clear_namespace(buf, hl_ns, 0, -1)
    end
  end
end

-- Add the virtual cursor, taking care to handle the cases where:
-- - the virtualedit option is being used and the cursor is in a
--   tab character or past the end of the line
-- - the current line is empty
-- - there are multibyte characters on the line
---@param ns number
local function add_virt_cur(ns)
  local hint = require('hop.hint')

  local cur_info = vim.fn.getcurpos()
  local cur_row = cur_info[2] - 1
  local cur_col = cur_info[3] - 1 -- this gives cursor column location, in bytes
  local cur_offset = cur_info[4]
  local virt_col = cur_info[5] - 1
  local cur_line = api.nvim_get_current_line()

  -- first check to see if cursor is in a tab char or past end of line or in empty line
  if cur_offset ~= 0 or #cur_line == cur_col then
    api.nvim_buf_set_extmark(0, ns, cur_row, cur_col, {
      virt_text = { { '█', 'Normal' } },
      virt_text_win_col = virt_col,
      priority = hint.HintPriority.CURSOR,
    })
  else
    api.nvim_buf_set_extmark(0, ns, cur_row, cur_col, {
      -- end_col must be column of next character, in bytes
      end_col = vim.fn.byteidx(cur_line, vim.fn.charidx(cur_line, cur_col) + 1),
      hl_group = 'HopCursor',
      priority = hint.HintPriority.CURSOR,
    })
  end
end

--- verify that column value is always smaller than line length
---@param wctx WindowContext
local function sanitize_cols(wctx)
  local start_line = api.nvim_buf_get_lines(wctx.buf_handle, wctx.line_range[1], wctx.line_range[1] + 1, false)
  if #start_line < wctx.column_range[1] then
    wctx.column_range[1] = #start_line
  end
  local end_line = api.nvim_buf_get_lines(wctx.buf_handle, wctx.line_range[2], wctx.line_range[2] + 1, false)
  if #end_line < wctx.column_range[2] then
    wctx.column_range[2] = #end_line
  end
end

-- Dim everything out to prepare the hop session for all windows
---@param hint_state HintState
---@param opts Options
local function apply_dimming(hint_state, opts)
  local hint = require('hop.hint')
  local window = require('hop.window')

  if not opts.dim_unmatched then
    return
  end

  for _, wctx in ipairs(hint_state.all_ctxs) do
    -- Set the highlight of unmatched lines of the buffer.
    sanitize_cols(wctx)
    local start_line, end_line = window.line_range2extmark(wctx.line_range)
    local start_col, end_col = window.column_range2extmark(wctx.column_range)
    api.nvim_buf_set_extmark(wctx.buf_handle, hint_state.dim_ns, start_line, start_col, {
      end_line = end_line,
      end_col = end_col,
      hl_group = 'HopUnmatched',
      hl_eol = true,
      priority = hint.HintPriority.DIM,
    })

    -- Hide diagnostics
    for ns in pairs(hint_state.diag_ns) do
      vim.diagnostic.show(ns, wctx.buf_handle, nil, { virtual_text = false })
    end
  end

  -- Add the virtual cursor
  if opts.virtual_cursor then
    add_virt_cur(hint_state.hl_ns)
  end
end

-- Get pattern from input for hint and preview
---@param prompt string
---@param maxchar number|nil
---@param opts Options|nil
---@return string|nil
function M.get_input_pattern(prompt, maxchar, opts)
  local hint = require('hop.hint')
  local jump_target = require('hop.jump_target')
  local jump_regex = require('hop.jump_regex')

  local hs = {}
  if opts then
    hs = hint.create_hint_state(opts)
    hs.preview_ns = api.nvim_create_namespace('hop_preview')
    apply_dimming(hs, opts)
  end

  local pat_keys = {}
  ---@type string|nil
  local pat = ''

  while true do
    pat = vim.fn.join(pat_keys, '')

    if opts and #pat > 0 then
      clear_namespace(hs.buf_list, hs.preview_ns)
      local ok, re = pcall(jump_regex.regex_by_case_searching, pat, false, opts)
      if ok then
        local jump_target_gtr = jump_target.jump_target_generator(re, hs.all_ctxs)
        local generated = jump_target_gtr(opts)
        hint.set_hint_preview(hs.preview_ns, generated.jump_targets)
      end
    end

    api.nvim_echo({}, false, {})
    vim.cmd.redraw()
    api.nvim_echo({ { prompt, 'Question' }, { pat } }, false, {})

    local ok, key = pcall(vim.fn.getcharstr)
    if not ok then -- Interrupted by <C-c>
      pat = nil
      break
    end

    if key == K_Esc then
      pat = nil
      break
    elseif key == K_CR or key == K_NL then
      break
    elseif key == K_BS or key == K_C_H then
      pat_keys[#pat_keys] = nil
    else
      pat_keys[#pat_keys + 1] = key
    end

    if maxchar and #pat_keys >= maxchar then
      pat = vim.fn.join(pat_keys, '')
      break
    end
  end

  if opts then
    clear_namespace(hs.buf_list, hs.preview_ns)
    -- quit only when got nothin for pattern to avoid blink of highlight
    if not pat then
      M.quit(hs)
    end
  end
  api.nvim_echo({}, false, {})
  vim.cmd.redraw()
  return pat
end

-- Move the cursor to a given location.
-- This function will update the jump list.
---@param jt JumpTarget
---@param opts Options Add option to shift cursor by column offset
function M.move_cursor_to(jt, opts)
  local hint = require('hop.hint')
  local jump_target = require('hop.jump_target')

  -- If it is pending for operator shift pos.col to the right by 1
  if api.nvim_get_mode().mode == 'no' and opts.direction ~= hint.HintDirection.BEFORE_CURSOR then
    jt.cursor.col = jt.cursor.col + 1
  end

  jump_target.move_jump_target(jt, 0, opts.hint_offset)

  -- Update the jump list
  -- There is bug with set extmark neovim/neovim#17861
  api.nvim_set_current_win(jt.window)
  --local cursor = api.nvim_win_get_cursor(0)
  --api.nvim_buf_set_mark(jt.buffer, "'", cursor[1], cursor[2], {})
  vim.cmd("normal! m'")
  api.nvim_win_set_cursor(jt.window, { jt.cursor.row, jt.cursor.col })
end

---@param jump_target_gtr Generator
---@param opts Options
function M.hint_with(jump_target_gtr, opts)
  M.hint_with_callback(jump_target_gtr, opts, function(jt)
    M.move_cursor_to(jt, opts)
  end)
end

---@param regex Regex
---@param opts Options
---@param callback function|nil
function M.hint_with_regex(regex, opts, callback)
  local jump_target = require('hop.jump_target')

  local jump_target_gtr = jump_target.jump_target_generator(regex)

  M.hint_with_callback(jump_target_gtr, opts, callback or function(jt)
    M.move_cursor_to(jt, opts)
  end)
end

---@param jump_target_gtr function
---@param opts Options
---@param callback function
function M.hint_with_callback(jump_target_gtr, opts, callback)
  local hint = require('hop.hint')

  if not M.initialized then
    vim.notify('Hop is not initialized; please call the setup function', vim.log.levels.ERROR)
    return
  end

  -- create hint state
  local hs = hint.create_hint_state(opts)

  -- create jump targets
  local generated = jump_target_gtr(opts, hs.all_ctxs)
  local jump_target_count = #generated.jump_targets

  local target_idx = nil
  if jump_target_count == 0 then
    target_idx = 0
  elseif vim.v.count > 0 then
    target_idx = vim.v.count
  elseif jump_target_count == 1 and opts.jump_on_sole_occurrence then
    target_idx = 1
  end

  if target_idx ~= nil then
    local jt = generated.jump_targets[target_idx]
    if jt then
      callback(jt)
    else
      eprintln(' -> there’s no such thing we can see…', opts.teasing)
    end

    clear_namespace(hs.buf_list, hs.hl_ns)
    clear_namespace(hs.buf_list, hs.dim_ns)
    return
  end

  -- we have at least two targets, so generate hints to display
  hs.hints = hint.create_hints(generated.jump_targets, generated.indirect_jump_targets, opts)

  apply_dimming(hs, opts)
  hint.set_hint_extmarks(hs.hl_ns, hs.hints, opts)
  vim.cmd.redraw()

  local h = nil
  while h == nil do
    local ok, key = pcall(vim.fn.getcharstr)
    if not ok then
      M.quit(hs)
      break
    end

    -- Special keys are string and start with 128 see :h getchar
    local not_special_key = true
    if key and key:byte() == 128 then
      not_special_key = false
    end

    -- If this is a key used in Hop (via opts.keys), deal with it in Hop
    -- otherwise quit Hop
    if not_special_key and opts.keys:find(key, 1, true) then
      h = M.refine_hints(key, hs, callback, opts)
      vim.cmd.redraw()
    else
      M.quit(hs)
      -- If the captured key is not the quit_key, pass it through
      -- to nvim to be handled normally (including mappings)
      if key ~= api.nvim_replace_termcodes(opts.quit_key, true, false, true) then
        api.nvim_feedkeys(key, '', true)
      end
      break
    end
  end
end

-- Refine hints in the given buffer.
--
-- Refining hints allows to advance the state machine by one step. If a terminal step is reached, this function jumps to
-- the location. Otherwise, it stores the new state machine.
function M.refine_hints(key, hint_state, callback, opts)
  local hint = require('hop.hint')

  local h, hints = hint.reduce_hints(hint_state.hints, key)

  if h == nil then
    if #hints == 0 then
      eprintln('no remaining sequence starts with ' .. key, opts.teasing)
      return
    end

    hint_state.hints = hints

    clear_namespace(hint_state.buf_list, hint_state.hl_ns)
    hint.set_hint_extmarks(hint_state.hl_ns, hints, opts)
  else
    M.quit(hint_state)

    callback(h.jump_target)
    return h
  end
end

-- Quit Hop and delete its resources.
---@param hint_state HintState
function M.quit(hint_state)
  clear_namespace(hint_state.buf_list, hint_state.hl_ns)
  clear_namespace(hint_state.buf_list, hint_state.dim_ns)

  for _, buf in ipairs(hint_state.buf_list) do
    -- sometimes, buffers might be unloaded; that’s the case with floats for instance (we can invoke Hop from them but
    -- then they disappear); we need to check whether the buffer is still valid before trying to do anything else with
    -- it
    if api.nvim_buf_is_valid(buf) then
      for ns in pairs(hint_state.diag_ns) do
        vim.diagnostic.show(ns, buf)
      end
    end
  end
end

---@param opts Options
function M.hint_words(opts)
  local jump_regex = require('hop.jump_regex')

  opts = override_opts(opts)
  M.hint_with_regex(jump_regex.regex_by_word_start(), opts)
end

---@param opts Options
function M.hint_camel_case(opts)
  local jump_regex = require('hop.jump_regex')

  opts = override_opts(opts)
  M.hint_with_regex(jump_regex.regex_by_camel_case(), opts)
end

---@param opts Options
---@param pattern string|nil
function M.hint_patterns(opts, pattern)
  if not M.initialized then
    vim.notify('Hop is not initialized; please call the setup function', vim.log.levels.ERROR)
    return
  end

  local jump_regex = require('hop.jump_regex')

  opts = override_opts(opts)

  -- The pattern to search is either retrieved from the (optional) argument
  -- or directly from user input.
  local pat
  if pattern then
    pat = pattern
  else
    vim.cmd.redraw()
    vim.fn.inputsave()
    pat = M.get_input_pattern('Hop pattern: ', nil, opts)
    vim.fn.inputrestore()
    if not pat then
      return
    end
  end

  if #pat == 0 then
    eprintln('-> empty pattern', opts.teasing)
    return
  end

  M.hint_with_regex(jump_regex.regex_by_case_searching(pat, false, opts), opts)
end

---@param opts Options
function M.hint_char1(opts)
  local jump_regex = require('hop.jump_regex')

  opts = override_opts(opts)

  local c = M.get_input_pattern('Hop 1 char: ', 1)
  if not c then
    return
  end
  M.hint_with_regex(jump_regex.regex_by_case_searching(c, true, opts), opts)
end

---@param opts Options
function M.hint_char2(opts)
  local jump_regex = require('hop.jump_regex')

  opts = override_opts(opts)

  local c = M.get_input_pattern('Hop 2 char: ', 2)
  if not c then
    return
  end
  M.hint_with_regex(jump_regex.regex_by_case_searching(c, true, opts), opts)
end

---@param opts Options
function M.hint_lines(opts)
  local jump_regex = require('hop.jump_regex')

  opts = override_opts(opts)
  M.hint_with_regex(jump_regex.by_line_start(), opts)
end

---@param opts Options
function M.hint_vertical(opts)
  local jump_regex = require('hop.jump_regex')

  opts = override_opts(opts)
  M.hint_with_regex(jump_regex.regex_by_vertical(), opts)
end

---@param opts Options
function M.hint_lines_skip_whitespace(opts)
  local jump_regex = require('hop.jump_regex')

  opts = override_opts(opts)
  M.hint_with_regex(jump_regex.regex_by_line_start_skip_whitespace(), opts)
end

---@param opts Options
function M.hint_anywhere(opts)
  local jump_regex = require('hop.jump_regex')

  opts = override_opts(opts)
  M.hint_with_regex(jump_regex.regex_by_anywhere(), opts)
end

-- Setup user settings.
function M.setup(opts)
  -- Look up keys in user-defined table with fallback to defaults.
  M.opts = setmetatable(opts or {}, { __index = require('hop.defaults') })
  M.initialized = true

  -- Load dict of match mappings
  if #M.opts.match_mappings > 0 then
    M.opts.loaded_mappings = {}
    for _, map in ipairs(M.opts.match_mappings) do
      local val = require('hop.mappings.' .. map)
      if val ~= nil then
        M.opts.loaded_mappings[map] = val
      end
    end
  end

  -- Insert the highlights and register the autocommand if asked to.
  local highlight = require('hop.highlight')
  highlight.insert_highlights()

  if M.opts.create_hl_autocmd then
    highlight.create_autocmd()
  end

  -- register Hop extensions, if any
  if M.opts.extensions ~= nil then
    for _, ext_name in pairs(M.opts.extensions) do
      local ok, extension = pcall(require, ext_name)
      if not ok then
        vim.notify(string.format('extension %s wasn’t correctly loaded', ext_name), vim.log.levels.ERROR)
      else
        if extension.register == nil then
          vim.notify(string.format('extension %s lacks the register function', ext_name), vim.log.levels.ERROR)
        else
          extension.register(M.opts)
        end
      end
    end
  end
end

return M
