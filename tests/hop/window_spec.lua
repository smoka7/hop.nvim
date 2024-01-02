local hop_window = require('hop.window')
local eq = assert.are.same

describe('Hop window:', function()
  it('cell2char and WindowCell with zh_sc characters', function()
    local line = 'abcd测试ABCD'

    local cell = 3
    local idx = hop_window.cell2char(line, cell)
    eq('d测试ABCD', vim.fn.strcharpart(line, idx))

    cell = 6
    idx = hop_window.cell2char(line, cell)
    eq('试ABCD', vim.fn.strcharpart(line, idx))

    cell = 7
    idx = hop_window.cell2char(line, cell)
    eq('试ABCD', vim.fn.strcharpart(line, idx))

    cell = 8
    idx = hop_window.cell2char(line, cell)
    eq('ABCD', vim.fn.strcharpart(line, idx))
  end)

  it('WindowCol and WindowChar with zh_sc characters', function()
    local line = 'abcd测试ABCD'

    local char = 5
    local idx = vim.fn.byteidx(line, char)
    eq('试ABCD', vim.fn.strpart(line, idx))
    idx = vim.fn.charidx(line, idx)
    eq('试ABCD', vim.fn.strcharpart(line, idx))

    char = 9
    idx = vim.fn.byteidx(line, char)
    eq('D', vim.fn.strpart(line, idx))
    idx = vim.fn.charidx(line, idx)
    eq('D', vim.fn.strcharpart(line, idx))
  end)
end)
