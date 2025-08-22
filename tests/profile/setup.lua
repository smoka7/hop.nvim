local profile_helpers = require('profile_helpers')

profile_helpers.timing('setup (default)', function()
  local hop = require('hop')

  hop.setup({
    match_mappings = {},
  })
end)

vim.cmd('quit!')
