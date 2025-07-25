---Require a module from the filter directory.
local old_require = require
pandoc.require = function(modname) -- luacheck: ignore 122
   return pandoc.system.with_working_directory(
      pandoc.path.directory(PANDOC_SCRIPT_FILE),
      function() return old_require(modname) end
   )
end
require = pandoc.require -- luacheck: ignore 121

local parse_attr = require('lib/parse-attr')
local crossrefs = require('lib/crossrefs')
local numbering = require('lib/numbering')

-- Table of Ids and corresponding cross-referenceable elements. To be populated
-- by various element numbering functions.
---@type table<string, {type: ('sec'|'fig'|'tbl'|'eqn'), number: string}>
IDs = {}

---@type Filter
return {
   {
      Table = parse_attr.parse_table_attr,
      Inlines = parse_attr.parse_equation_attr,
   },
   {
      Span = parse_attr.remove_temp_classes,
   },
   {
      Inlines = crossrefs.parse_crossrefs,
   },
   {
      -- Number cross-referenceable elements and construct table with Ids and numbers.
      traverse = 'topdown', -- needed for subfigs
      Pandoc = numbering.number_sections,
      Span = numbering.number_equations,
      Figure = numbering.number_fig_or_tbl,
      Table = numbering.number_fig_or_tbl,
   },
   {
      traverse = 'topdown',
      Span = crossrefs.write_crossrefs,
   },
}
