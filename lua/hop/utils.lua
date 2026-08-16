local api = vim.api
local M = {}

-- Create namespace for specified window and name
---@param window integer Window id, or 0 for current window
---@param name string Namespace name or empty string
---@param clear boolean Clear namespace after creation
---@return integer # Namespace id
function M.create_namespace(window, name, clear)
  local name_window = string.format("%s_%s", name, window)
  local ns_id = api.nvim_create_namespace(name_window)
  if clear then
    M.clear_namespace(window, ns_id, 0, -1)
  end
  if api.nvim__ns_set and api.nvim_win_is_valid(window) then
    api.nvim__ns_set(ns_id, {
      wins = {window},
    })
  elseif api.nvim__win_add_ns and api.nvim_win_is_valid(window) then
    api.nvim__win_add_ns(window, ns_id)
  end
  return ns_id
end

-- Clear namespace for specified window and namespace id
---@param window integer Window id, or 0 for current window
---@param ns_id integer Namespace to clear, or -1 to clear all namespaces.
---@param line_start integer Start of range of lines to clear
---@param line_end integer End of range of lines to clear (exclusive) or -1 to clear
function M.clear_namespace(window, ns_id, line_start, line_end)
  if api.nvim_win_is_valid(window) then
    local buf_id = api.nvim_win_get_buf(window)
    if api.nvim_buf_is_valid(buf_id) then
      api.nvim_buf_clear_namespace(buf_id, ns_id, line_start, line_end)
    end
  end
end

-- Wrapper to the vim.api.nvim_buf_set_extmark
---@param buffer integer Buffer id, or 0 for current buffer
---@param ns_id integer Namespace id from `nvim_create_namespace()`
---@param line integer Line where to place the mark, 0-based. `api-indexing`
---@param col integer Column where to place the mark, 0-based. `api-indexing`
---@param opts vim.api.keyset.set_extmark Optional parameters.
---@return integer # Id of the created/updated extmark
function M.buf_set_extmark(buffer, ns_id, line, col, opts)
  if vim.fn.has("nvim-0.10.0") == 1 then
    opts.scoped = true
  end
  return api.nvim_buf_set_extmark(buffer, ns_id, line, col, opts)
end

return M
