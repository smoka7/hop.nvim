local hop = require('hop')
local eq = assert.are.same
local api = vim.api
local hop_helpers = require('hop_helpers')

local override_keyseq = hop_helpers.override_keyseq

describe('Hop with virtualedit enabled:', function()
  before_each(function()
    vim.cmd.view('tests/tst_virtualedit.txt')
    hop.setup({ match_mappings = { 'zh_sc' } })

    vim.o.wrap = false
    vim.wo[0].virtualedit = 'all'
  end)

  it('hint_lines', function()
    vim.api.nvim_win_set_cursor(0, { 1, 20 })

    vim.cmd.normal({ args = { '8zl' }, bang = true })
    vim.cmd.normal({ args = { 'lh' }, bang = true })

    override_keyseq({ 'r' }, hop.hint_lines)
    local curpos = vim.fn.getcurpos(0)
    eq(12, curpos[2])
    eq(5, curpos[3])
    eq(4, curpos[4])
  end)

  it('hint_vertical', function()
    vim.api.nvim_win_set_cursor(0, { 1, 20 })
    local col = vim.fn.wincol()

    override_keyseq({ 'h' }, hop.hint_vertical)
    local curpos = vim.fn.getcurpos(0)
    eq(6, curpos[2])
    eq(21, curpos[3])
    eq(4, curpos[4])
    eq(col, vim.fn.wincol())

    vim.cmd.normal({ args = { '8zl' }, bang = true })
    vim.cmd.normal({ args = { 'lh' }, bang = true })
    col = col - 8

    override_keyseq({ 'l' }, hop.hint_vertical)
    curpos = vim.fn.getcurpos(0)
    eq(10, curpos[2])
    eq(21, curpos[3])
    eq(4, curpos[4])
    eq(col, vim.fn.wincol())
  end)
end)
