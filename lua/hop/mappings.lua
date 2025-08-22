local M = {}

-- Load the table for an item in match-mappings, returns cache once loaded.
---@param name string Name of the mapping
---@param opts Options
function get_mapping(name, opts)
  if opts.loaded_mappings[name] then
    return opts.loaded_mappings[name]
  end

  local ok, val = pcall(require, 'hop.mappings.' .. name)
  if not ok then
    vim.notify(string.format('Hop can’t load "%s" (in match_mappings)', name), vim.log.levels.ERROR)
  end

  opts.loaded_mappings[name] = val or {}

  return opts.loaded_mappings[name]
end

-- Checkout match-mappings with key from each pattern character
---@param pat string Pattern to search inputed from user
---@param opts Options
function M.checkout(pat, opts)
  local dict_pat = ''

  for k = 1, #pat do
    local char = pat:sub(k, k)
    local dict_char_pat = ''
    -- checkout dict-char pattern from each mapping dict
    for _, v in ipairs(opts.match_mappings) do
      local mapping = get_mapping(v, opts)
      local val = mapping[char]
      if val ~= nil then
        dict_char_pat = dict_char_pat .. val
      end
    end

    if dict_char_pat ~= '' then
      dict_pat = dict_pat .. '[' .. vim.fn.escape(dict_char_pat, ']^-\\') .. ']'
    end
  end

  return dict_pat
end

return M
