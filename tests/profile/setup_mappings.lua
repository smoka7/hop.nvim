local profile_helpers = require('profile_helpers')

profile_helpers.timing('setup match_mappings', function()
  local hop = require('hop')

  hop.setup({
    match_mappings = { 'fa', 'zh', 'zh_sc', 'zh_tc' },
  })
end)

vim.cmd('quit!')
