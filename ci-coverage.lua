#!/usr/bin/env -S pandoc lua

-- Prints overall coverage and exits with code 1 unless it's 100.00%.

local home = os.getenv('HOME')
package.path = home
   .. '/.luarocks/share/lua/5.4/?.lua;'
   .. home
   .. '/.luarocks/share/lua/5.4/?/init.lua;'
   .. package.path
package.cpath = home .. '/.luarocks/lib/lua/5.4/?.so;' .. package.cpath

local reporter = require('luacov.reporter')
local ReporterBase = reporter.ReporterBase

local R = setmetatable({}, ReporterBase)
R.__index = R

local RED_BOLD = '\27[1;91m'
local RESET = '\27[0m'

function R:on_start()
   self.total_hits, self.total_miss = 0, 0
   self.per_file = {} -- filename -> {hits=..., miss=...}
end

-- Called for each executed (hit) executable line
function R:on_hit_line(filename)
   self.total_hits = self.total_hits + 1
   local f = self.per_file[filename]
   if not f then
      f = { hits = 0, miss = 0 }
      self.per_file[filename] = f
   end
   f.hits = f.hits + 1
end

-- Called for each executable line that was NOT executed
function R:on_mis_line(filename)
   self.total_miss = self.total_miss + 1
   local f = self.per_file[filename]
   if not f then
      f = { hits = 0, miss = 0 }
      self.per_file[filename] = f
   end
   f.miss = f.miss + 1
end

function R:on_end()
   local total_exec = self.total_hits + self.total_miss
   local overall = (total_exec == 0) and 100 or (self.total_hits / total_exec * 100)

   if overall >= 100.0 then
      -- All good: no output, success exit
      return
   end

   -- Build per-file rows
   local rows, maxw = {}, #'Filename'
   for fname, fm in pairs(self.per_file) do
      local exec = fm.hits + fm.miss
      local pct = (exec == 0) and 100 or (fm.hits / exec * 100)
      rows[#rows + 1] = { fname = fname, pct = pct }
      if #fname > maxw then maxw = #fname end
   end
   table.sort(rows, function(a, b) return a.fname < b.fname end)

   -- Render table
   local header = string.format('%-' .. maxw .. 's  %s', 'Filename', 'Coverage')
   local rule = string.rep('─', #header)
   local out = pandoc.List { header, rule }

   for _, r in ipairs(rows) do
      local pct_str = string.format('%6.2f%%', r.pct)
      local fname_str = string.format('%-' .. maxw .. 's', r.fname)
      local row = fname_str .. '   ' .. pct_str
      if r.pct < 100.0 then row = RED_BOLD .. row .. RESET end
      out:insert(row)
   end

   io.stderr:write(table.concat(out, '\n') .. '\n')
   os.exit(1) -- fail the build when < 100%
end

reporter.report(R)
