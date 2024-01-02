local hop = require('hop')
local eq = assert.are.same
local api = vim.api
local hop_helpers = require('hop_helpers')

local override_keyseq = hop_helpers.override_keyseq

describe('Hop with match mappings:', function()
  before_each(function()
    vim.cmd.view('tests/tst_mappings_zh.txt')
    hop.setup({ match_mappings = { 'zh', 'zh_sc', 'zh_tc' } })
  end)

  describe('hint_char1,', function()
    before_each(function()
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
    end)

    it('zh', function()
      override_keyseq({ ',' }, hop.hint_char1)
      eq({ 2, 58 }, api.nvim_win_get_cursor(0))
    end)

    it('zh_sc', function()
      override_keyseq({ 'f', 's' }, hop.hint_char1)
      eq({ 2, 72 }, api.nvim_win_get_cursor(0))
    end)

    it('zh_tc', function()
      override_keyseq({ 'f', 'a' }, hop.hint_char1)
      eq({ 3, 52 }, api.nvim_win_get_cursor(0))
    end)
  end)

  it('hint_vertical', function()
    vim.o.wrap = false
    vim.wo[0].virtualedit = 'none'
    vim.api.nvim_win_set_cursor(0, { 1, 65 })
    local col = vim.fn.wincol()

    override_keyseq({ 'a' }, hop.hint_vertical)
    eq({ 2, 72 }, api.nvim_win_get_cursor(0))
    eq(col, vim.fn.wincol())

    vim.cmd.normal({ args = { '16zl' }, bang = true })
    -- It's seemd a neovim's bug.
    -- I have to move right then left back here, to guarantee the next cursor is {3, 72}.
    -- Or the next cursor will be still {2, 72}.
    vim.cmd.normal({ args = { 'lh' }, bang = true })
    col = col - 16

    override_keyseq({ 'a' }, hop.hint_vertical)
    eq({ 3, 72 }, api.nvim_win_get_cursor(0))
    eq(col, vim.fn.wincol())
  end)
end)
