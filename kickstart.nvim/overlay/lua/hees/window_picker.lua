-- Pick the window a file opens in from the explorer. kickstart's neo-tree already maps `w` to
-- open_with_window_picker; it only needs nvim-window-picker installed. Each window shows a big
-- letter: press it, or click the window.

vim.pack.add { { src = 'https://github.com/s1n7ax/nvim-window-picker', version = vim.version.range '2.*' } }

require('window-picker').setup {
  hint = 'floating-big-letter',
  selection_chars = 'FJDKSLAGHRUEIWOQP',
  picker_config = { handle_mouse_click = true },
  prompt_message = 'Pick window (letter or click, Esc cancels): ',
  filter_rules = {
    autoselect_one = true,
    include_current_win = false,
    bo = {
      filetype = { 'neo-tree', 'neo-tree-popup', 'notify', 'fidget', 'hees-menu' },
      buftype = { 'terminal', 'quickfix', 'prompt' },
    },
  },
}
