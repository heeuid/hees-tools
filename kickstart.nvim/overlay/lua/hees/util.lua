-- Shared helpers for the hees overlay: data directory, JSON state, icons.

local M = {}

M.is_win = vim.fn.has 'win32' == 1

--- Directory for overlay data (NES state, logs). Lives next to the config, not in stdpath('data'),
--- so everything this setup writes stays in one place. Override with $HEES_NVIM_DATA.
---@param ... string sub directories
---@return string
function M.data_dir(...)
  local base = vim.env.HEES_NVIM_DATA or vim.fs.joinpath(vim.fn.stdpath 'config', 'data')
  local dir = vim.fs.joinpath(base, ...)
  vim.fn.mkdir(dir, 'p')
  return dir
end

---@param path string
---@param default table
---@return table
function M.read_json(path, default)
  local f = io.open(path, 'r')
  if not f then return vim.deepcopy(default) end
  local text = f:read '*a'
  f:close()
  local ok, value = pcall(vim.json.decode, text)
  if not ok or type(value) ~= 'table' then return vim.deepcopy(default) end
  return vim.tbl_deep_extend('keep', value, default)
end

---@param path string
---@param value table
function M.write_json(path, value)
  local f = assert(io.open(path, 'w'))
  f:write(vim.json.encode(value))
  f:close()
end

--- Icons that render without a Nerd Font fall back to plain Unicode shapes found in common
--- monospace fonts (Cascadia, JetBrains Mono, DejaVu), never emoji.
local nerd = {
  check = '\u{f00c}', -- nf-fa-check  shows: 
  submenu = '\u{f0da}', -- nf-fa-caret_right  shows: 
  breakpoint = '\u{f111}', -- nf-fa-circle  shows: 
  breakpoint_cond = '\u{f059}', -- nf-fa-question_circle  shows: 
  breakpoint_rejected = '\u{f05e}', -- nf-fa-ban  shows: 
  logpoint = '\u{f05a}', -- nf-fa-info_circle  shows: 
  stopped = '\u{f061}', -- nf-fa-arrow_right  shows: 
  ai = '\u{f06a9}', -- nf-md-robot  shows: 󰚩
  spinner = { '\u{f0a9e}', '\u{f0a9f}', '\u{f0aa0}', '\u{f0aa1}', '\u{f0aa2}', '\u{f0aa3}', '\u{f0aa4}', '\u{f0aa5}' }, -- nf-md-circle_slice_1..8  shows: 󰪞 󰪟 󰪠 󰪡 󰪢 󰪣 󰪤 󰪥
}
local plain = {
  check = '✓',
  submenu = '▸',
  breakpoint = '●',
  breakpoint_cond = '◆',
  breakpoint_rejected = '○',
  logpoint = '◇',
  stopped = '▶',
  ai = '✦',
  spinner = { '◐', '◓', '◑', '◒' },
}

---@return table
function M.icons() return vim.g.have_nerd_font and nerd or plain end

--- Pretty-print a key sequence for menus: '<leader>sf' -> 'Space s f'.
---@param keys string?
---@return string?
function M.key_hint(keys)
  if not keys then return nil end
  local leader = vim.g.mapleader == ' ' and 'Space ' or ((vim.g.mapleader or '\\') .. ' ')
  return (keys:gsub('<leader>', leader))
end

return M
