local utils = require('lib.utils')

local M = {}

---Parse a Table Attr if it is present in the Table's caption. Pandoc does not
---yet support Attrs to be used in Table captions.
---@param tbl Table
---@return Table | nil
M.parse_table_attr = function(tbl)
   if #tbl.caption.long > 0 then
      -- When writing the caption back to Markdown, we need to ensure the
      -- Markdown isn't wrapped, otherwise lines other than the first won't be
      -- interpreted as part of the header when reading the Markdown back in.
      local md_caption = pandoc.write(pandoc.Pandoc(tbl.caption.long), 'markdown', { wrap_text = 'none' })
      -- The syntax for defining a table attr is the same as for a header.
      local md_header = '# ' .. md_caption
      local header = pandoc.read(md_header, 'markdown-auto_identifiers').blocks[1]
      if not (#tbl.attr.identifier > 0) then tbl.attr = header.attr end
      tbl.caption.long = header.content ~= pandoc.Inlines {} and pandoc.Plain(header.content) or pandoc.Blocks {}
      return tbl
   end
end

---For Markdown input, parses an Equation Attr if it follows the
---Equation. Pandoc does not yet support Attrs to be used with Equations
---and the Pandoc Math AST element does not include an Attr.
---@param inlines Inlines
---@return Inline[] | nil
M.parse_equation_attr = function(inlines)
   -- The Math element in pandoc's AST does not currently include an Attr.
   -- We can use a Span containing a Math element to represent Math with an
   -- Attr instead.

   local inlines_modified = false
   -- Go from end-1 to start to avoid problems with changing indices.
   for i = #inlines, 1, -1 do
      local elt, next_elt = inlines[i], inlines[i + 1]
      if utils.is_display_math(elt) then
         ---@type Math
         local math = elt
         if next_elt and next_elt.tag == 'Str' and next_elt.text:sub(1, 1) == '{' then
            local md_inlines = pandoc.write(pandoc.Pandoc(pandoc.Plain { table.unpack(inlines, i + 1) }), 'markdown')
            local md_bracketed_span = '[]' .. md_inlines
            local bracketed_span_inlines = pandoc.read(md_bracketed_span, 'markdown').blocks[1].content
            ---@cast bracketed_span_inlines Inlines
            if bracketed_span_inlines[1].tag == 'Span' then
               local attr = bracketed_span_inlines[1].attr
               inlines[i] = pandoc.Span(math, attr)
               ---@type List<Inline>
               inlines = pandoc.Inlines(
                  pandoc.List { table.unpack(inlines, 1, i) } .. pandoc.List { table.unpack(bracketed_span_inlines, 2) }
               )
            else
               -- Wrap Math in Span. If all DisplayMath elements are
               -- wrapped in a Span, the subsequent filter functions are
               -- less complex.
               -- Assign placeholder class as a workaround for https://github.com/jgm/pandoc/issues/10802
               inlines[i] = pandoc.Span(math, pandoc.Attr('', { 'temp-class-to-prevent-empty-attr' }))
            end
         else
            -- Wrap Math in Span.
            -- Assign placeholder class as a workaround for https://github.com/jgm/pandoc/issues/10802
            inlines[i] = pandoc.Span(math, pandoc.Attr('', { 'temp-class-to-prevent-empty-attr' }))
         end
         inlines_modified = true
      end
   end

   if inlines_modified then return inlines end
end

---Remove temporary class from Spans with otherwise empty Attrs. This needs to
---be done after all equation Attrs have been parsed, otherwise nested Spans
---would cause problems. See https://github.com/jgm/pandoc/issues/10802.
---@param span Span
---@return Span | nil
M.remove_temp_classes = function(span)
   if span.classes:includes('temp-class-to-prevent-empty-attr') then
      span.classes = {}
      return span
   end
end

return M
