local M = {}

---@param name string
---@param func function
function M.timing(name, func)
  local t_start = vim.uv.hrtime()
  func()
  local t_end = vim.uv.hrtime()
  local diff = t_end - t_start

  print(string.format("Time elapsed: %9s\t%s\n", diff, name))
end

return M
