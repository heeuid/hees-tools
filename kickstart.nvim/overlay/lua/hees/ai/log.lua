-- Record of every AI request (next edits and analysis): the command that ran, its working
-- directory, the prompt sent on stdin, raw stdout/stderr, the answer file, exit code, timing and
-- outcome. Finished requests are appended verbatim to <config>/data/ai/logs/<date>.jsonl, one JSON
-- object per line; running ones are kept in memory so the viewer can show them live.

local util = require 'hees.util'

local M = {}

-- Fields written to disk (handles and callbacks on the entry are left out).
local FIELDS = {
  'uid', 'id', 'kind', 'task', 'title', 'time', 'backend', 'model', 'cwd', 'argv', 'prompt', 'stdout', 'stderr', 'answer',
  'code', 'signal', 'elapsed', 'status', 'reason', 'outcome', 'file', 'range', 'conv', 'turn', 'question', 'dropped_turns',
}

local session = {} ---@type table[] this session's entries, oldest first
local listeners = {} ---@type fun()[]
local seq = 0

local function changed()
  for _, fn in ipairs(listeners) do
    pcall(fn)
  end
end

function M.dir() return util.data_dir('ai', 'logs') end

---@param time integer
function M.file_for(time) return vim.fs.joinpath(M.dir(), os.date('%Y-%m-%d', time) .. '.jsonl') end

--- Call `fn` whenever an entry starts or finishes.
---@param fn fun()
function M.subscribe(fn) table.insert(listeners, fn) end

--- Start an entry for a request that is about to run.
---@param fields table kind, title, backend, model, cwd, argv, prompt, …
---@return table entry
function M.begin(fields)
  seq = seq + 1
  local now = os.time()
  local entry = vim.tbl_extend('force', fields, {
    uid = ('%d-%d-%d'):format(now, vim.fn.getpid(), seq),
    id = seq,
    time = now,
    status = 'running',
  })
  table.insert(session, entry)
  changed()
  return entry
end

--- Append a finished entry to today's file.
---@param entry table
function M.finish(entry)
  local record = {}
  for _, k in ipairs(FIELDS) do
    record[k] = entry[k]
  end
  local f = io.open(M.file_for(entry.time), 'a')
  if f then
    f:write(vim.json.encode(record), '\n')
    f:close()
  end
  changed()
end

--- Entries of this session plus the last `days` days on disk, newest first.
---@param days integer?
---@return table[]
function M.all(days)
  local list, seen = {}, {}
  for _, e in ipairs(session) do
    seen[e.uid] = true
    table.insert(list, e)
  end
  for d = 0, (days or 3) - 1 do
    local f = io.open(M.file_for(os.time() - d * 86400), 'r')
    if f then
      for line in f:lines() do
        local ok, e = pcall(vim.json.decode, line, { luanil = { object = true, array = true } })
        if ok and type(e) == 'table' and e.uid and not seen[e.uid] then
          seen[e.uid] = true
          table.insert(list, e)
        end
      end
      f:close()
    end
  end
  table.sort(list, function(a, b)
    if a.time ~= b.time then return a.time > b.time end
    return (a.uid or '') > (b.uid or '')
  end)
  return list
end

return M
