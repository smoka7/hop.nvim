local perm = require('hop.perm')
local window = require('hop.window')
local api = vim.api

---@class Hint
---@field label string|nil
---@field jump_target JumpTarget

---@class HintState
---@field buf_list integer[]
---@field all_ctxs WindowContext[]
---@field hints Hint[]
---@field hl_ns integer
---@field dim_ns integer
---@field preview_ns integer
---@field diag_ns table

local M = {}

---@enum HintDirection
M.HintDirection = {
  BEFORE_CURSOR = 1,
  AFTER_CURSOR = 2,
}

---@enum HintPosition
M.HintPosition = {
  BEGIN = 1,
  MIDDLE = 2,
  END = 3,
}

---@enum HintType
M.HintType = {
  OVERLAY = 'overlay',
  INLINE = 'inline',
}

---@enum HintPriority
-- Magic constants for highlight priorities;
--
-- Priorities are ranged on 16-bit integers; 0 is the least priority and 2^16 - 1 is the higher.
-- We want Hop to override everything so we use a very high priority for grey (2^16 - 3 = 65533); hint
-- priorities are one level above (2^16 - 2) and the virtual cursor one level higher (2^16 - 1), which
-- is the higher.
M.HintPriority = {
  DIM = 65533,
  HINT = 65534,
  CURSOR = 65535,
}

-- Manhattan distance with column and row, weighted on x so that results are more packed on y.
---@param a CursorPos
---@param b CursorPos
---@param x_bias number
---@return number
function M.manh_distance(a, b, x_bias)
  return (x_bias * math.abs(b.row - a.row)) + math.abs(b.col - a.col)
end

--- Distance method that prioritises hints based on the
--- left to right reading distance
---@param a CursorPos Cursor Position
---@param b CursorPos Jump target position
---@param x_bias number
---@return number 
function M.readwise_distance(a, b, x_bias)
  return (100 * math.abs(b.row - a.row)) + (b.col - a.col)
end

-- Reduce a hint.
-- This function will remove hints not starting with the input key and will reduce the other ones
-- with one level.
---@param label string
---@param key string
---@return string|nil
local function reduce_label(label, key)
  local snd_idx = vim.fn.byteidx(label, 1)
  if label:sub(1, snd_idx) == key then
    label = label:sub(snd_idx + 1)
  end

  if label == '' then
    return nil
  end

  return label
end

-- Reduce all hints and return the one fully reduced, if any.
---@param hints Hint[]
---@param key string
---@return Hint|nil,Hint[]
function M.reduce_hints(hints, key)
  local next_hints = {}

  for _, h in pairs(hints) do
    local prev_label = h.label
    h.label = reduce_label(h.label, key)

    if h.label == nil then
      return h, {}
    elseif h.label ~= prev_label then
      next_hints[#next_hints + 1] = h
    end
  end

  return nil, next_hints
end

-- Create hints from jump targets.
--
-- This function associates jump targets with permutations, creating hints. A hint is then a jump target along with a
-- label.
--
-- If `indirect_jump_targets` is `nil`, `jump_targets` is assumed already ordered with all jump target with the same
-- score (0)
---@param jump_targets JumpTarget[]
---@param indirect_jump_targets IndirectJumpTarget[]
---@param opts Options
---@return Hint[]
function M.create_hints(jump_targets, indirect_jump_targets, opts)
  ---@type Hint[]
  local hints = {}
  local perms = perm.permutations(opts.keys, #jump_targets, opts)

  -- get or generate indirect_jump_targets
  if indirect_jump_targets == nil then
    indirect_jump_targets = {}

    for i = 1, #jump_targets do
      indirect_jump_targets[i] = { index = i, score = 0 }
    end
  end

  for i, indirect in pairs(indirect_jump_targets) do
    hints[indirect.index] = {
      label = table.concat(perms[i]),
      jump_target = jump_targets[indirect.index],
    }
  end

  return hints
end

-- Create hint state
---@param opts Options
---@return HintState
function M.create_hint_state(opts)
  ---@type HintState
  local hint_state = {}

  hint_state.all_ctxs = window.get_windows_context(opts)
  hint_state.buf_list = {}
  local buf_sets = {}
  for _, wctx in ipairs(hint_state.all_ctxs) do
    if not buf_sets[wctx.buf_handle] then
      buf_sets[wctx.buf_handle] = true
      hint_state.buf_list[#hint_state.buf_list + 1] = wctx.buf_handle
    end
    -- Ensure all window contexts are cliped for hint state
    window.clip_window_context(wctx, opts)
  end

  -- Create the highlight groups; the highlight groups will allow us to clean everything at once when Hop quits
  hint_state.hl_ns = api.nvim_create_namespace('hop_hl')
  hint_state.dim_ns = api.nvim_create_namespace('hop_dim')

  -- Clear namespaces in case last hop operation failed before quitting
  for _, buf in ipairs(hint_state.buf_list) do
    if api.nvim_buf_is_valid(buf) then
      api.nvim_buf_clear_namespace(buf, hint_state.hl_ns, 0, -1)
      api.nvim_buf_clear_namespace(buf, hint_state.dim_ns, 0, -1)
    end
  end

  -- Backup namespaces of diagnostic
  hint_state.diag_ns = vim.diagnostic.get_namespaces()

  return hint_state
end

-- Create the extmarks for per-line hints.
---@param hl_ns integer
---@param hints Hint[]
---@param opts Options
function M.set_hint_extmarks(hl_ns, hints, opts)
  for _, hint in pairs(hints) do
    local label = hint.label
    if opts.uppercase_labels and label ~= nil then
      label = label:upper()
    end

    local virt_text = { { label, 'HopNextKey' } }
    -- Get the byte index of the second hint so that we can slice it correctly
    if label ~= nil and vim.fn.strdisplaywidth(label) ~= 1 then
      local snd_idx = vim.fn.byteidx(label, 1)
      virt_text = { { label:sub(1, snd_idx), 'HopNextKey1' }, { label:sub(snd_idx + 1), 'HopNextKey2' } }
    end

    local row, col = window.pos2extmark(hint.jump_target.cursor)
    api.nvim_buf_set_extmark(hint.jump_target.buffer, hl_ns, row, col, {
      virt_text = virt_text,
      virt_text_pos = opts.hint_type,
      hl_mode = opts.hl_mode,
      priority = M.HintPriority.HINT,
    })
  end
end

---@param hl_ns integer
---@param jump_targets JumpTarget[]
function M.set_hint_preview(hl_ns, jump_targets)
  for _, jt in ipairs(jump_targets) do
    local row, col = window.pos2extmark(jt.cursor)
    api.nvim_buf_set_extmark(jt.buffer, hl_ns, row, col, {
      end_row = row,
      end_col = col + jt.length,
      hl_group = 'HopPreview',
      hl_eol = true,
      priority = M.HintPriority.HINT,
    })
  end
end

return M
