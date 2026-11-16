-- What the language servers know about the code being analyzed: attached servers, diagnostics in
-- the range, hover at the cursor, where the symbol under the cursor is defined (with its source)
-- and used, the document outline, and the function or class enclosing the cursor. The requests
-- are sent together and waited for at most `timeout_ms` in total; anything a server hasn't
-- answered by then (e.g. still indexing the workspace) is simply left out.

local M = {}

M.timeout_ms = 3000
M.max_symbols = 80
M.max_references = 15
M.definition_lines = 30

local SEVERITY = { 'ERROR', 'WARN', 'INFO', 'HINT' }
-- LSP SymbolKind: 5 class, 6 method, 9 constructor, 10 enum, 11 interface, 12 function, 23 struct.
local CALLABLE = { [6] = true, [9] = true, [12] = true }
local CONTAINER = { [5] = true, [10] = true, [11] = true, [23] = true }

local function kind_name(kind) return vim.lsp.protocol.SymbolKind[kind] or tostring(kind) end

local function rel(path) return vim.fn.fnamemodify(path, ':~:.') end

--- Send several requests at once and wait for all of them, at most M.timeout_ms in total.
--- Returns, per method, the results of every client that answered.
---@param buf integer
---@param requests table<string, table|fun(client: vim.lsp.Client): table> method -> params
---@return table<string, any[]>
local function request_all(buf, requests)
  local results, pending = {}, 0
  for method, params in pairs(requests) do
    results[method] = {}
    pending = pending + 1
    local ok = pcall(vim.lsp.buf_request_all, buf, method, params, function(responses)
      for _, r in pairs(responses or {}) do
        if r.result then table.insert(results[method], r.result) end
      end
      pending = pending - 1
    end)
    if not ok then pending = pending - 1 end
  end
  vim.wait(M.timeout_ms, function() return pending <= 0 end, 20)
  return results
end

local function position_params(win)
  return function(client) return vim.lsp.util.make_position_params(win, client.offset_encoding) end
end

--- Flatten DocumentSymbol trees (or SymbolInformation lists) into { name, kind, first, last, depth }.
local function flatten(symbols, depth, out)
  for _, s in ipairs(symbols or {}) do
    local range = s.range or (s.location and s.location.range)
    if range then
      table.insert(out, { name = s.name, kind = s.kind, first = range.start.line + 1, last = range['end'].line + 1, depth = depth })
    end
    flatten(s.children, depth + 1, out)
  end
  return out
end

local function locations(result)
  local list = vim.islist(result) and result or { result }
  local out = {}
  for _, loc in ipairs(list) do
    local uri = loc.uri or loc.targetUri
    local range = loc.range or loc.targetSelectionRange or loc.targetRange
    if uri and range then table.insert(out, { path = vim.uri_to_fname(uri), line = range.start.line + 1 }) end
  end
  return out
end

local function source_at(path, line, count)
  local buf = vim.fn.bufadd(path)
  vim.fn.bufload(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, line - 1, line - 1 + count, false)
  for i, l in ipairs(lines) do
    lines[i] = ('%d| %s'):format(line + i - 1, l)
  end
  return lines, vim.bo[buf].filetype
end

---@class hees.ai.LspContext
---@field clients string[]
---@field diagnostics string[]
---@field hover string[]
---@field definition { path: string, line: integer, lines: string[], filetype: string }?
---@field references string[]
---@field reference_count integer
---@field outline string[]
---@field enclosing { name: string, kind: string, first: integer, last: integer }?

--- Collect LSP information for `buf` around the cursor of `win`, diagnostics limited to
--- lines `first`..`last` (1-based).
---@return hees.ai.LspContext
function M.collect(buf, win, first, last)
  local ctx = { clients = {}, diagnostics = {}, hover = {}, references = {}, reference_count = 0, outline = {} }
  for _, c in ipairs(vim.lsp.get_clients { bufnr = buf }) do
    table.insert(ctx.clients, c.name)
  end

  for _, d in ipairs(vim.diagnostic.get(buf)) do
    local line = d.lnum + 1
    if line >= first and line <= last then
      table.insert(ctx.diagnostics, ('L%d %s%s %s'):format(line, SEVERITY[d.severity] or '?', d.source and (' [' .. d.source .. ']') or '', (d.message:gsub('\n', ' '))))
    end
  end
  if #ctx.clients == 0 then return ctx end

  local cursor = vim.api.nvim_win_get_cursor(win)
  local res = request_all(buf, {
    ['textDocument/hover'] = position_params(win),
    ['textDocument/definition'] = position_params(win),
    ['textDocument/references'] = function(client)
      local p = vim.lsp.util.make_position_params(win, client.offset_encoding)
      p.context = { includeDeclaration = false }
      return p
    end,
    ['textDocument/documentSymbol'] = { textDocument = vim.lsp.util.make_text_document_params(buf) },
  })

  for _, r in ipairs(res['textDocument/hover']) do
    if r.contents then vim.list_extend(ctx.hover, vim.lsp.util.convert_input_to_markdown_lines(r.contents)) end
  end

  for _, r in ipairs(res['textDocument/definition']) do
    local loc = locations(r)[1]
    if loc and not ctx.definition then
      local lines, ft = source_at(loc.path, loc.line, M.definition_lines)
      ctx.definition = { path = rel(loc.path), line = loc.line, lines = lines, filetype = ft }
    end
  end

  for _, r in ipairs(res['textDocument/references']) do
    for _, loc in ipairs(locations(r)) do
      ctx.reference_count = ctx.reference_count + 1
      if #ctx.references < M.max_references then table.insert(ctx.references, ('%s:%d'):format(rel(loc.path), loc.line)) end
    end
  end

  local symbols = {}
  for _, r in ipairs(res['textDocument/documentSymbol']) do
    flatten(r, 0, symbols)
  end
  local best
  for i, s in ipairs(symbols) do
    if i <= M.max_symbols then table.insert(ctx.outline, ('%s%s %s (L%d-%d)'):format(('  '):rep(s.depth), kind_name(s.kind), s.name, s.first, s.last)) end
    if s.first <= cursor[1] and cursor[1] <= s.last and (CALLABLE[s.kind] or CONTAINER[s.kind]) then
      -- Prefer the innermost function; a class only when no function encloses the cursor.
      local better = not best or (CALLABLE[s.kind] and not CALLABLE[best.kind]) or (CALLABLE[s.kind] == CALLABLE[best.kind] and s.last - s.first < best.last - best.first)
      if better then best = s end
    end
  end
  if best then ctx.enclosing = { name = best.name, kind = kind_name(best.kind), first = best.first, last = best.last } end
  return ctx
end

return M
