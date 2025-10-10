---Require a module from the filter directory.
local require = function(modname) -- luacheck: ignore 122
   return pandoc.system.with_working_directory(
      pandoc.path.directory(PANDOC_SCRIPT_FILE),
      function() return require(modname) end
   )
end

local parse_attr = require('lib/parse-attr')
local crossrefs = require('lib/crossrefs')
local numbering = require('lib/numbering')

-- Table of Ids and corresponding cross-referenceable elements. To be populated
-- by various element numbering functions.
---@type table<string, {type: ('sec'|'fig'|'tbl'|'eqn'), number: string}>
IDs = {}

---@param doc Pandoc
function Pandoc(doc)
   if FORMAT == 'docx' and PANDOC_WRITER_OPTIONS.extensions:includes('native_numbering') then
      pandoc.log.warn('`native_numbering` extension must not be used. Exiting.')
      return
   end
   if FORMAT == 'docx' and PANDOC_WRITER_OPTIONS.extensions:includes('number_sections') then
      pandoc.log.warn(
         '`number_sections` extension must not be used with DOCX. '
            .. 'Instead, associate a Number Format with your Heading style in your reference-doc. '
            .. 'Exiting.'
      )
      return
   end

   return doc:walk({
      Table = parse_attr.parse_table_attr,
      Inlines = parse_attr.parse_equation_attr,
   })
      :walk({
         Span = parse_attr.remove_temp_classes,
      })
      :walk({
         Inlines = crossrefs.parse_crossrefs,
      })
      :walk({
         Figure = numbering.move_unnumbered_class,
      })
      :walk({
         -- Number cross-referenceable elements and construct table with Ids and numbers.
         traverse = 'topdown', -- needed for subfigs
         Pandoc = numbering.number_sections,
         Span = function(span)
            if FORMAT ~= 'docx' then return numbering.number_equations(span) end
         end,
         Para = function(para)
            if FORMAT == 'docx' then return numbering.number_docx_equations(para) end
         end,
         Figure = numbering.number_fig_or_tbl,
         Table = numbering.number_fig_or_tbl,
      })
      :walk({
         -- Resolve cross-reference groups.
         Span = crossrefs.write_crossrefs,
      })
      :walk {
         -- Resolve single cross-references.
         Link = crossrefs.write_crossref,
      }
end
