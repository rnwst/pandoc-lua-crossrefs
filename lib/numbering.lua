local utils = require('lib.utils')

local numbering = {}

numbering.number_sections = function(doc)
   -- Pandoc numbers sections automatically if the `--number-sections` option
   -- is passed, however we need to have access to these numbers to number
   -- corresponding cross-references. If the `--number-sections` option is
   -- not passed, we also need to number sections (unfortunately, modifying
   -- `PANDOC_WRITER_OPTIONS` inside of a filter has no effect).

   -- Pandoc numbers the first smallest level header in a document '1',
   -- irrespective of what this level is. Therefore, to replicate this behavior,
   -- we first need to determine the smallest header level (the level of
   -- the header which is printed in the largest font) in the document. The
   -- largest header level (header which is printed smallest) is needed to
   -- determine the length of the 'counters' table. If `--number-offset` was
   -- supplied, the header level offsets need to be considered as well.
   local smallest_header_level = PANDOC_WRITER_OPTIONS.number_offset:find_if(function(int) return int ~= 0 end)
   local largest_header_level
   doc:walk {
      ---@param header Header
      Header = function(header)
         if not header.classes:includes('unnumbered') then
            if smallest_header_level == nil or header.level < smallest_header_level then
               smallest_header_level = header.level
            end
            if largest_header_level == nil or header.level > largest_header_level then
               largest_header_level = header.level
            end
         end
      end,
   }
   -- Early return if doc has no headers!
   if not largest_header_level then return end

   ---@type List<integer>
   local counters = pandoc.List {}
   for i = 1, largest_header_level - smallest_header_level + 1 do
      counters[i] = PANDOC_WRITER_OPTIONS.number_offset[i + smallest_header_level - 1] or 0
   end

   return doc:walk {
      ---@param header Header
      Header = function(header)
         if not header.classes:includes('unnumbered') then
            -- Increment header counters and reset higher levels.
            local counter_level = header.level - smallest_header_level + 1
            local previous_counter = counters[counter_level]
            counters[counter_level] = previous_counter + 1
            -- Reset counters of higher levels.
            for i = counter_level + 1, #counters do
               counters[i] = 0
            end
            -- Create header number.
            local number = table.concat(counters, '.', 1, counter_level)
            -- Populate table with Ids.
            if header.identifier ~= nil then IDs[header.identifier] = { type = 'sec', number = number } end
            -- If `number_sections` is not specified, number section.
            if not PANDOC_WRITER_OPTIONS.number_sections then
               header.attributes['number'] = number
               header.content:insert(1, pandoc.Space())
               local span = pandoc.Span({ pandoc.Str(number) }, pandoc.Attr('', { 'header-section-number' }))
               header.content:insert(1, span)
               return header
            end
         end
      end,
   }
end

-- Other equation numbering schemes such as 'chapter.number' are yet to be
-- implemented.
local equation_number = 0
---Number equations (DisplayMath elements).
---@param span Span
---@return Span | RawInline | Math | nil
numbering.number_equations = function(span)
   -- A Span containing a Math element is Math with an Attr.
   if #span.content == 1 and utils.is_display_math(span.content[1]) then
      if FORMAT == 'docx' then
         -- Equation numbering for DOCX output currently causes a formatting
         -- issue (left-aligned instead of centered display equations), and
         -- therefore equation numbering has been temporarily disabled until a
         -- fix is found for this issue.
         return span.content[1] --[[@as Math]]
      else
         if not span.classes:includes('unnumbered') then
            equation_number = equation_number + 1
            if span.identifier ~= nil then
               IDs[span.identifier] = { type = 'eqn', number = tostring(equation_number) }
            end
            span.classes:insert('display-math-container')
            span.content[2] = pandoc.Space()
            span.content[3] =
               pandoc.Span({ pandoc.Str('(' .. equation_number .. ')') }, pandoc.Attr('', { 'display-math-label' }))
            return span
         else
            -- Unnumbered equations do not need an equation container. However, we still
            -- need to preserve the Span's Attr.
            if utils.html_formats:includes(FORMAT) then
               local math_method = PANDOC_WRITER_OPTIONS.html_math_method
               if type(math_method) == 'table' then math_method = math_method['method'] end

               -- Other math_methods yet to be implemented.
               if math_method == 'katex' then
                  span.classes:insert(1, 'math')
                  local math = span.content[1]
                  local math_class = math.mathtype == 'InlineMath' and 'inline' or 'display'
                  span.classes:insert(1, math_class)
                  span.content[1] = pandoc.RawInline('html', utils.html_escape(math.text))
                  local html = pandoc.write(pandoc.Pandoc { span }, 'html')
                  return pandoc.RawInline('html', html)
               end
            end
         end
      end
   end
end

local figure_number = 0
local table_number = 0
---Number figure or table.
---@param fig_or_tbl (Figure | Table)
---@return (Figure | Table), false  Numbered Figure or Table, or `nil` if unnumbered
---@overload fun(fig_or_tbl: Figure | Table): nil
numbering.number_fig_or_tbl = function(fig_or_tbl)
   if not fig_or_tbl.classes:includes('unnumbered') then
      ---@type string
      local type
      ---@type integer
      local number
      ---@type string
      local label_class
      ---@type fun(num: integer): string
      local number_formatter = function(num) return tostring(num) end
      ---@type fun(num: integer): string
      local label_formatter
      ---@type boolean
      local colon_after_label = true

      if fig_or_tbl.tag == 'Figure' then
         type = 'fig'
         figure_number = figure_number + 1
         number = figure_number
         label_class = 'figure-label'
         label_formatter = function(num) return string.format('Fig.\u{A0}%s', num) end
      end

      if fig_or_tbl.tag == 'Table' then
         type = 'tbl'
         table_number = table_number + 1
         number = table_number
         label_class = 'table-label'
         label_formatter = function(num) return string.format('Tbl.\u{A0}%s', num) end
      end

      ---Add Fig or Tbl to table of Ids, prepend label to caption.
      ---@param elt (Figure | Table)
      local function process_fig_or_tbl(elt)
         if elt.identifier ~= '' then IDs[elt.identifier] = { type = type, number = number_formatter(number) } end
         local caption_prefix = pandoc.Span({ pandoc.Str(label_formatter(number)) }, pandoc.Attr('', { label_class }))
         if
            not (
               pandoc.List({ 'docx', 'opendocument', 'odt' }):includes(FORMAT)
               and PANDOC_WRITER_OPTIONS.extensions:includes('native_numbering')
            )
         then
            -- If figure or table caption is not empty, append colon to number.
            if #elt.caption.long ~= 0 and colon_after_label then
               caption_prefix.content[1].text = caption_prefix.content[1].text .. ':'
               elt.caption.long[1].content:insert(1, pandoc.Space())
            end
            elt.caption.long[1].content:insert(1, caption_prefix)
         end
      end

      process_fig_or_tbl(fig_or_tbl)

      -- Number subfigs.
      if type == 'fig' then
         number = 0
         number_formatter = function(num) return figure_number .. label_formatter(num) end
         label_formatter = function(num) return string.format('(%s)', string.char(96 + num)) end
         colon_after_label = false
         fig_or_tbl = fig_or_tbl:walk {
            Figure = function(subfig)
               number = number + 1
               process_fig_or_tbl(subfig)
               return subfig
            end,
         }
      end

      return fig_or_tbl, false -- Return `false` as second value to avoid processing subfigures again.
   end
end

return numbering
