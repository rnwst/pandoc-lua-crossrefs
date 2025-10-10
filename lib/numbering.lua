local utils = require('lib.utils')

local M = {}

---Move class `unnumbered` from Image to containing Figure.
---@param fig Figure
---@return Figure?
M.move_unnumbered_class = function(fig)
   if
      #fig.content == 1
      and fig.content[1].tag == 'Plain'
      and #fig.content[1].content == 1
      and fig.content[1].content[1].tag == 'Image'
   then
      local img = fig.content[1].content[1]
      ---@cast img Image
      if img.classes:includes('unnumbered') then
         img.classes:remove(img.classes:find('unnumbered')[2])
         fig.classes:insert('unnumbered')
         return fig
      end
   end
end

local docx_bmk_id = 100000 -- large number to prevent collisions with bookmark Ids used by pandoc.

local function get_docx_bmk_id()
   docx_bmk_id = docx_bmk_id + 1
   return docx_bmk_id
end

M.number_sections = function(doc)
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
            -- In the case of DOCX output, numbering must be done by associating
            -- a Number Format with the relevant Heading style in the
            -- reference-doc.
            if not PANDOC_WRITER_OPTIONS.number_sections and FORMAT ~= 'docx' then
               header.attributes['number'] = number
               header.content:insert(1, pandoc.Space())
               local span = pandoc.Span({ pandoc.Str(number) }, pandoc.Attr('', { 'header-section-number' }))
               header.content:insert(1, span)
               return header
            elseif FORMAT == 'docx' then
               -- Need to insert bookmarks so that sections can be referenced
               -- later. Pandoc inserts bookmarks for entire sections (header
               -- + content), so we cannot simply reuse the Header's Id as the
               -- bookmark name (so we append `_number`).
               local id = get_docx_bmk_id()
               header.content:insert(
                  1,
                  pandoc.RawInline(
                     'openxml',
                     string.format(
                        [[

                  <w:bookmarkStart w:id="%s" w:name="%s" />]],
                        id,
                        header.identifier .. '_number'
                     )
                  )
               )
               header.content:insert(pandoc.RawInline(
                  'openxml',
                  string.format(
                     [[

                  <w:bookmarkEnd w:id="%s" />]],
                     id
                  )
               ))
               return header
            end
         elseif FORMAT == 'docx' then
            -- Prevent section from being numbered.
            header.content:insert(
               1,
               pandoc.RawInline(
                  'openxml',
                  [[

              <w:pPr>
                <w:numPr>
                  <w:numId w:val="0" />
                </w:numPr>
              </w:pPr>]]
               )
            )
            return header
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
M.number_equations = function(span)
   -- A Span containing a Math element is Math with an Attr.
   if #span.content == 1 and utils.is_display_math(span.content[1]) then
      if not span.classes:includes('unnumbered') then
         equation_number = equation_number + 1
         if span.identifier ~= nil then IDs[span.identifier] = { type = 'eqn', number = tostring(equation_number) } end
         span.classes:insert('display-math-container')
         span.content[2] = pandoc.Space()
         span.content[3] =
            pandoc.Span({ pandoc.Str('(' .. equation_number .. ')') }, pandoc.Attr('', { 'display-math-label' }))
         return span
      end
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

---Number equations when output format is DOCX.
---@param para Para
---@return Para[]?
M.number_docx_equations = function(para)
   local paras = pandoc.Blocks {}
   local current_idx = 1
   -- In DOCX, captions are block-level elements. Therefore, we need to
   -- terminate a paragraph after every equation and insert a RawBlock
   -- containing the equation caption.
   for i, inline in ipairs(para.content) do
      -- A Span containing a Math element is Math with an Attr.
      if
         inline.tag == 'Span'
         and #inline.content == 1
         and utils.is_display_math(inline.content[1])
         and not inline.classes:includes('unnumbered')
      then
         equation_number = equation_number + 1
         if inline.identifier ~= nil then
            IDs[inline.identifier] = { type = 'eqn', number = tostring(equation_number) }
         end
         -- Flatten equation.
         para.content[i] = inline.content[1]
         -- Insert previous para content.
         paras:insert(pandoc.Para { table.unpack(para.content, current_idx, i) })
         current_idx = i + 1
         -- Insert equation caption.
         local id = get_docx_bmk_id()
         paras:insert(pandoc.RawBlock(
            'openxml',
            string.format(
               [[

               <w:p>
                 <w:pPr>
                   <w:pStyle w:val="EquationCaption" />
                 </w:pPr>
                 <w:r>
                   <w:t>(</w:t>
                 </w:r>
                 <w:bookmarkStart w:id="%s" w:name="%s" />
                 <w:r>
                   <w:fldChar w:fldCharType="begin" />
                 </w:r>
                 <w:r>
                   <w:instrText xml:space="preserve"> SEQ Equation \* ARABIC </w:instrText>
                 </w:r>
                 <w:r>
                   <w:fldChar w:fldCharType="separate" />
                 </w:r>
                 <w:r>
                   <w:t>%s</w:t>
                 </w:r>
                 <w:r>
                   <w:fldChar w:fldCharType="end" />
                 </w:r>
                 <w:bookmarkEnd w:id="%s" />
                 <w:r>
                   <w:t>)</w:t>
                 </w:r>
               </w:p>]],
               id,
               inline.identifier .. '_number',
               equation_number,
               id
            )
         ))
      end
   end
   -- Add remaining para content.
   if #para.content >= current_idx then paras:insert(pandoc.Para { table.unpack(para.content, current_idx) }) end
   if #paras > 1 then return paras end
end

local figure_number = 0
local table_number = 0
---Number figure or table.
---Filter is run in 'topdown' mode so subfigures are processed later.
---@param fig_or_tbl (Figure | Table)
---@return (Figure | Table), false  Numbered Figure or Table, or `nil` if unnumbered
---@overload fun(fig_or_tbl: Figure | Table): nil
M.number_fig_or_tbl = function(fig_or_tbl)
   if not fig_or_tbl.classes:includes('unnumbered') then
      ---@type string
      local _type
      ---@type string
      local prefix
      ---@type integer
      local number
      ---@type string
      local label_class
      -- Needed for subfigs. Used to format the number in the figure/table label.
      ---@type fun(num: integer): string
      local number_formatter = function(num) return tostring(num) end
      -- Needed for subfigs. Used to format the number in the cross-reference.
      ---@type fun(num: integer): string
      local ref_number_formatter = number_formatter
      ---@type boolean
      local colon_after_label = true

      if fig_or_tbl.tag == 'Figure' then
         _type = 'fig'
         prefix = 'Fig.\u{A0}'
         figure_number = figure_number + 1
         number = figure_number
         label_class = 'figure-label'
      end

      if fig_or_tbl.tag == 'Table' then
         _type = 'tbl'
         prefix = 'Tbl.\u{A0}'
         table_number = table_number + 1
         number = table_number
         label_class = 'table-label'
      end

      ---Add Fig or Tbl to table of Ids, prepend label to caption.
      ---@param elt (Figure | Table)
      local function process_fig_or_tbl(elt)
         if elt.identifier ~= '' then IDs[elt.identifier] = { type = _type, number = ref_number_formatter(number) } end
         local caption_prefix = pandoc.Inlines {}
         if FORMAT == 'docx' then
            local docx_elt_prefix = string.format(

               [[
               <w:r>
                 <w:rPr>
                   <w:noProof />
                 </w:rPr>
                 <w:t xml:space="preserve">%s</w:t>
               </w:r>]],
               prefix
            )
            local seq = (_type == 'fig' and 'Figure' or 'Table')
            local docx_elt_number = string.format(
               [[

               <w:fldSimple w:instr=" SEQ %s \* ARABIC ">
                 <w:r>
                   <w:t>%s</w:t>
                 </w:r>
               </w:fldSimple>]],
               seq,
               number
            )
            local docx_caption_prefix = docx_elt_prefix .. docx_elt_number
            -- Only insert bookmarks if element can actually be referenced.
            if elt.identifier ~= '' then
               -- High numbered to prevent clashes with pandoc's bookmark Ids.
               local label_id = get_docx_bmk_id()
               local number_id = get_docx_bmk_id()

               docx_elt_number = string.format([[

               <w:bookmarkStart w:id="%s" w:name="%s" />]] .. docx_elt_number .. [[
               <w:bookmarkEnd w:id="%s" />
               ]], number_id, elt.identifier .. '_number', number_id)

               docx_caption_prefix = string.format([[

               <w:bookmarkStart w:id="%s" w:name="%s" />]] .. docx_elt_prefix .. docx_elt_number .. [[
               <w:bookmarkEnd w:id="%s" />]], label_id, elt.identifier .. '_label', label_id)
            end
            caption_prefix:insert(pandoc.RawInline('openxml', docx_caption_prefix))
            -- If figure or table caption is not empty, append colon.
            if #elt.caption.long ~= 0 then
               if colon_after_label then caption_prefix:insert(pandoc.Str(':')) end
               caption_prefix:insert(pandoc.Space())
            end
         else
            local label_span =
               pandoc.Span({ pandoc.Str(prefix .. number_formatter(number)) }, pandoc.Attr('', { label_class }))
            -- If figure or table caption is not empty, append colon to number.
            -- This should become part of the Span, so that it is affected by
            -- relevant CSS in HTML output.
            if #elt.caption.long ~= 0 then
               if colon_after_label then label_span.content:insert(pandoc.Str(':')) end
               label_span.content:insert(pandoc.Space())
            end
            caption_prefix:insert(label_span)
         end

         if #elt.caption.long ~= 0 then
            elt.caption.long[1].content = caption_prefix .. elt.caption.long[1].content
         else
            elt.caption.long:insert(pandoc.Plain(caption_prefix))
         end
      end

      process_fig_or_tbl(fig_or_tbl)

      -- Number subfigs.
      if _type == 'fig' then
         prefix = ''
         number = 0
         number_formatter = function(num) return string.format('(%s)', string.char(96 + num)) end
         ref_number_formatter = function(num) return figure_number .. number_formatter(num) end
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

return M
