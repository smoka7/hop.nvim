local hop = require('hop')
local hop_hint = require('hop.hint')
local mock = require('luassert.mock')
local stub = require('luassert.stub')
local api = vim.api
local eq = assert.are.same

local function override_getcharstr(override, closure)
  local charstr = stub(vim.fn, 'getcharstr')

  charstr.returns(override())
  local r = closure()

  mock.revert(charstr)

  return r
end

describe('Hop movement is correct', function()
  before_each(function()
    vim.cmd.enew({ bang = true })
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {
      'abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxy',
    })
    hop.setup()
  end)

  it('Hop is initialized', function()
    eq(hop.initialized, true)
  end)

  it('HopChar1AC', function()
    vim.api.nvim_win_set_cursor(0, { 1, 1 })

    local key_counter = 0
    override_getcharstr(function()
      key_counter = key_counter + 1
      if key_counter == 1 then
        return 'c'
      end
      if key_counter == 2 then
        return 'a'
      end
    end, function()
      hop.hint_char1({ direction = hop_hint.HintDirection.AFTER_CURSOR })
    end)

    local end_pos = api.nvim_win_get_cursor(0)

    eq(end_pos[2], 3)
  end)
end)
