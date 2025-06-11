-- If the filter wasn't called from this directory (which usually won't be the
-- case), we need to adjust the paths by which modules in subdirectories are
-- loaded.
-- Uncomment for debugging purposes:
-- local old_require = require
-- local function require(modname)
--    local prefix = pandoc.path.directory(PANDOC_SCRIPT_FILE)
--    modname = pandoc.path.join { prefix, modname }
--    return old_require(modname)
-- end

-- local logging = require 'logging.logging'

-- <Utilities> ---------------------------------------------------------------------------------------------------------

---@type List<string>
local html_formats = pandoc.List {
   'chunkedhtml',
   'html',
   'html5',
   'html4',
   'slideous',
   'slidy',
   'dzslides',
   'revealjs',
   's5',
}

---HTML-escape string.
---@param str string
---@return string
local function html_escape(str)
   local entities = {
      ['&'] = '&amp;',
      ['<'] = '&lt;',
      ['>'] = '&gt;',
      ['"'] = '&quot;',
      ["'"] = '&#39;',
   }
   local escaped_str = str:gsub('[&<>\'"]', entities)
   return escaped_str
end

---Check if AST element is DisplayMath.
---@param inline Inline
---@return boolean
local function is_display_math(inline) return inline.tag == 'Math' and inline.mathtype == 'DisplayMath' end

---Check if AST element is a cross-reference (a cross-reference is a Span with class 'cross-ref').
---@param inline Inline
---@return boolean
local function is_crossref(inline) return inline and inline.tag == 'Span' and inline.classes:includes('cross-ref') end

---Check if AST element is a cross-reference group (a Span with class 'cross-ref-group').
---@param inline Inline
---@return boolean
local function is_crossref_group(inline)
   return inline and inline.tag == 'Span' and inline.classes:includes('cross-ref-group')
end

-- </Utilities> --------------------------------------------------------------------------------------------------------

---Parse a Table Attr if it is present in the Table's caption. Pandoc does not
---yet support Attrs to be used in Table captions.
---@param tbl Table
---@return Table | nil
local function parse_table_attr(tbl)
   if #tbl.caption.long > 0 then
      -- When writing the caption back to Markdown, we need to ensure the
      -- Markdown isn't wrapped, otherwise lines other than the first won't be
      -- interpreted as part of the header when reading the Markdown back in.
      local md_caption = pandoc.write(pandoc.Pandoc(tbl.caption.long), 'markdown', { wrap_text = 'none' })
      -- The syntax for defining a table attr is the same as for a header.
      local md_header = '# ' .. md_caption
      local header = pandoc.read(md_header, 'markdown-auto_identifiers').blocks[1]
      tbl.attr = header.attr
      tbl.caption.long = pandoc.Plain(header.content)
      return tbl
   end
end

---Parse an Equation Attr if it follows the Equation. Pandoc does not yet
---support Attrs to be used with Equations and the Pandoc Math AST element does
---not include an Attr.
---@param inlines Inlines
---@return Inline[] | nil
local function parse_equation_attr(inlines)
   -- The Math element in pandoc's AST does not currently include an Attr.
   -- We can use a Span containing a Math element to represent Math with an
   -- Attr instead.

   local inlines_modified = false
   -- Go from end-1 to start to avoid problems with changing indices.
   for i = #inlines, 1, -1 do
      local elt, next_elt = inlines[i], inlines[i + 1]
      if is_display_math(elt) then
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
local function remove_temp_classes(span)
   if span.classes:includes('temp-class-to-prevent-empty-attr') then
      span.classes = {}
      return span
   end
end

---Parse a cross-reference in Pandoc's Markdown.
---@param str Str
---@return Inline[] | nil
local function parse_crossref(str)
   local opening_bracket, prefix_suppressor, id, closing_bracket, punctuation =
      str.text:match('^(%[?)(%-?)#([%a%d-_:%.]-)(%]?)([\\%p%)]-)$')
   if not id or id == '' then return end
   local only_internal_punctuation = id:find('^%a[%a%d-_:%.]*%a$') or id:find('%a')
   if not only_internal_punctuation then return end

   local crossref = pandoc.Span({}, pandoc.Attr('', { 'cross-ref' }))
   crossref.attributes.id = id
   if prefix_suppressor == '-' then crossref.classes:insert('suppress-prefix') end
   local elts = pandoc.List { crossref }
   if opening_bracket == '[' then elts:insert(1, pandoc.Str('[')) end
   if closing_bracket == ']' then elts:insert(pandoc.Str(']')) end
   if punctuation ~= '' then elts:insert(pandoc.Str(punctuation)) end

   return elts
end

---Parse cross-references in Inlines.
---@param inlines Inlines
---@return nil | Inline[], boolean?
local function parse_crossrefs(inlines)
   -- Parse cross-references into Spans.
   local new_inlines = inlines:walk { Str = parse_crossref }

   -- Early return if no cross-references were found!
   if new_inlines == inlines then return end

   inlines = new_inlines

   -- Now separate out any opening or closing brackets in Strs into separate
   -- Strs.
   inlines = inlines:walk {
      Str = function(str)
         if str.text:find('^%[.') then
            return { pandoc.Str('['), pandoc.Str(str.text:sub(2)) }
         elseif str.text:find('.%]$') then
            return { pandoc.Str(str.text:sub(1, -1)), pandoc.Str(']') }
         end
      end,
   }

   -- Now create cross-ref groups. Crossref Groups are represented by Spans of
   -- class 'cross-ref-group'.
   ---@type List<Inline>
   new_inlines = pandoc.List {}
   local i = 1
   while inlines[i] do
      if i < #inlines and inlines[i].tag == 'Str' and inlines[i].text == '[' then
         ---@type boolean
         local at_least_one_crossref = false
         ---@type List<Inline>
         local group_content = pandoc.List {}
         ---@type boolean
         local group_valid = false
         local j = i + 1
         while inlines[j] do
            local elt = inlines[j]
            if elt.tag == 'Str' and elt.text == ']' then
               if at_least_one_crossref then
                  group_valid = true
                  break
               else
                  group_valid = false
                  break
               end
               -- Another opening bracket invalidates the group if no cross-reference has yet been
               -- found. This ensures that the smallest possible Crossref Groups are created.
            elseif elt.tag == 'Str' and elt.text == '[' and not at_least_one_crossref then
               group_valid = false
               break
            else
               if is_crossref(elt) then at_least_one_crossref = true end
               group_content:insert(inlines[j])
            end
            j = j + 1
            if is_crossref(elt) and inlines[j] and inlines[j].tag == 'Str' then
               if inlines[j].text == ';' and inlines[j + 1] and inlines[j + 1].tag == 'Space' then
                  -- Skip punctuation following crossref if it is ';'.
                  j = j + 2
               elseif inlines[j].text == '\\;' then
                  -- To still allow a semicolon to be used to separate cross-references, an
                  -- escaped semicolon is converted to a semicolon.
                  group_content:insert(pandoc.Str(';'))
                  j = j + 1
               end
            end
         end
         if group_valid then
            -- Insert Crossref Group into inlines.
            local crossref_group = pandoc.Span(group_content, pandoc.Attr('', { 'cross-ref-group' }))
            new_inlines:insert(crossref_group)
            i = j
         else
            inlines:insert(inlines[i])
         end
      else
         new_inlines:insert(inlines[i])
      end
      i = i + 1
   end

   return new_inlines, false -- Nested cross-references are not allowed!
end

-- Table of Ids and corresponding cross-referenceable elements. To be populated
-- by various element numbering functions.
---@type table<string, {type: ('sec'|'fig'|'tbl'|'eqn'), number: string}>
local ids = {}

local function number_sections(doc)
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
            if header.identifier ~= nil then ids[header.identifier] = { type = 'sec', number = number } end
            -- If `number_sections` is not specified, number section.
            if not PANDOC_WRITER_OPTIONS.number_sections then
               header.attributes['number'] = number
               header.content:insert(1, pandoc.Space())
               local span = pandoc.Span({ pandoc.Str(number) }, pandoc.Attr('', { 'header-section-number' }))
               header.content:insert(1, span)
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
local function number_equations(span)
   -- A Span containing a Math element is Math with an Attr.
   if #span.content == 1 and is_display_math(span.content[1]) then
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
               ids[span.identifier] = { type = 'eqn', number = tostring(equation_number) }
            end
            span.classes:insert('display-math-container')
            span.content[2] = pandoc.Space()
            span.content[3] =
               pandoc.Span({ pandoc.Str('(' .. equation_number .. ')') }, pandoc.Attr('', { 'display-math-label' }))
            return span
         else
            -- Unnumbered equations do not need an equation container. However, we still
            -- need to preserve the Span's Attr.
            if html_formats:includes(FORMAT) then
               local math_method = PANDOC_WRITER_OPTIONS.html_math_method
               if type(math_method) == 'table' then math_method = math_method['method'] end

               -- Other math_methods yet to be implemented.
               if math_method == 'katex' then
                  span.classes:insert(1, 'math')
                  local math = span.content[1]
                  local math_class = math.mathtype == 'InlineMath' and 'inline' or 'display'
                  span.classes:insert(1, math_class)
                  span.content[1] = pandoc.RawInline('html', html_escape(math.text))
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
local function number_fig_or_tbl(fig_or_tbl)
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
         if elt.identifier ~= '' then ids[elt.identifier] = { type = type, number = number_formatter(number) } end
         local caption_prefix = pandoc.Span({ pandoc.Str(label_formatter(number)) }, pandoc.Attr('', { label_class }))
         -- If figure or table caption is not empty, append colon to number.
         if #elt.caption.long ~= 0 and colon_after_label then
            caption_prefix.content[1].text = caption_prefix.content[1].text .. ':'
            elt.caption.long:insert(1, pandoc.Space())
         end
         elt.caption.long:insert(1, caption_prefix)
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

---Get type of cross-reference target.
---@param crossref Span
---@return string
local function get_target_type(crossref)
   local target = ids[crossref.attributes.id]
   return target and target.type
end

---Whether element is a resolved cross-reference.
---@param elt Inline
---@return boolean
local function is_resolved_crossref(elt) return elt.tag == 'Link' and elt.classes:includes('cross-ref') end

---Separate adjacent elements of a certain kind with commas, and the last two
---elements with ", and ". If there are only two adjacent elements, insert " and "
---between them.
---@param inlines Inlines | Inline[]
---@param matches fun(elt: Inline): boolean
local function insert_separators(inlines, matches)
   ---@type List<integer>
   local adjacent_indices = pandoc.List {}
   for i = 2, #inlines do
      if matches(inlines[i]) and matches(inlines[i - 1]) then adjacent_indices:insert(i) end
   end

   if #adjacent_indices == 1 then
      inlines:insert(adjacent_indices[1], pandoc.Str(' and '))
   elseif #adjacent_indices > 1 then
      inlines:insert(adjacent_indices[#adjacent_indices], ', and ')
      -- Traverse list in reverse to avoid problems with changing indices.
      for i = #adjacent_indices - 1, 1, -1 do
         inlines:insert(adjacent_indices[i], ', ')
      end
   end
end

---Resolve cross-references.
---@param span Span
---@return (Link | Span), false? | nil, nil
---@overload fun(Span): nil
local function write_crossrefs(span)
   ---Resolve cross-reference.
   ---@param crossref Span cross-reference
   ---@param suppress_prefix? boolean whether to suppress prefixing the referenced object's type (e.g. 'Fig.' or 'Tbl.')
   ---@return Link | Span
   local function resolve_crossref(crossref, suppress_prefix)
      local id = crossref.attributes.id
      local target = ids[id]
      ---@type string
      local crossref_text = ''
      if target ~= nil then
         if not crossref.classes:includes('suppress-prefix') and not suppress_prefix then
            if target.type == 'sec' then
               crossref_text = 'Sec.\u{A0}' -- 0xA0 is a non-breaking space
            elseif target.type == 'fig' then
               crossref_text = 'Fig.\u{A0}'
            elseif target.type == 'tbl' then
               crossref_text = 'Tbl.\u{A0}'
            elseif target.type == 'eqn' then
               crossref_text = 'Eqn.\u{A0}'
            end
         end
         crossref_text = crossref_text .. target.number
      else
         crossref_text = '??'
         pandoc.log.warn('Cross-referenced element with id "' .. id .. '" could not be resolved.')
      end
      if html_formats:includes(FORMAT) then
         local link = pandoc.Link(crossref_text, '#' .. id)
         link.attr = pandoc.Attr('', { 'cross-ref' })
         return link
      else
         local crossref_span = pandoc.Span(crossref_text, pandoc.Attr('', { 'cross-ref' }))
         return crossref_span
      end
   end

   if is_crossref(span) then return resolve_crossref(span) end

   if is_crossref_group(span) then
      local inlines = span.content

      -- Special case: If a cross-ref group is made up of a single Str, followed
      -- by a Space, followed by a cross-ref with suppressed prefix, treat this
      -- as a cross-ref with a custom prefix.
      if
         #inlines == 3
         and inlines[1].tag == 'Str'
         and inlines[2].tag == 'Space'
         and is_crossref(inlines[3])
         and inlines[3].classes:includes('suppress-prefix')
      then
         ---@cast inlines[3] Span
         inlines[3] = resolve_crossref(inlines[3])
         inlines[3].content = inlines
         return inlines[3]
      end

      -- Traverse inlines in reverse order to avoid problems with shifting indices.
      for i = #inlines, 1, -1 do
         if is_crossref(inlines[i]) then
            local crossref = inlines[i]
            ---@cast crossref Span
            local target_type = get_target_type(crossref)
            if not target_type then
               inlines[i] = resolve_crossref(crossref)
               goto continue
            end
            ---@type List<integer>
            local crossref_indices = pandoc.List { i }
            local j = i
            local found_different_target_type = false
            while not found_different_target_type and j > 1 do
               j = j - 1
               if is_crossref(inlines[j]) then
                  local next_crossref = inlines[j]
                  ---@cast next_crossref Span
                  if get_target_type(next_crossref) == target_type then
                     crossref_indices:insert(1, j)
                  else
                     found_different_target_type = true
                  end
               end
            end
            -- First resolve crossrefs, then insert separators.
            if #crossref_indices == 1 then
               j = crossref_indices[1]
               inlines[j] = resolve_crossref(inlines[j] --[[@as Span]])
            else
               for _, idx in ipairs(crossref_indices) do
                  inlines[idx] = resolve_crossref(inlines[idx] --[[@as Span]], true)
               end
               local crossrefs_of_a_kind =
                  pandoc.Span({ table.unpack(inlines, j, i) }, pandoc.Attr('', { 'crossrefs-of-a-kind' }))
               crossrefs_of_a_kind.content:insert(1, pandoc.Space())
               local prefix = '??'
               if target_type == 'sec' then
                  prefix = 'Secs.'
               elseif target_type == 'fig' then
                  prefix = 'Figs.'
               elseif target_type == 'tbl' then
                  prefix = 'Tbls.'
               elseif target_type == 'eqn' then
                  prefix = 'Eqns.'
               end
               crossrefs_of_a_kind.content:insert(1, pandoc.Str(prefix))

               insert_separators(crossrefs_of_a_kind.content, is_resolved_crossref)

               for _ = j, i do
                  table.remove(inlines, j)
               end
               inlines:insert(j, crossrefs_of_a_kind)
            end
         end
         ::continue::
      end
      -- If there are any adjacent resolved cross-refs, they also need separators between them.
      insert_separators(
         inlines,
         function(elt)
            return is_resolved_crossref(elt) or (elt.tag == 'Span' and elt.classes:includes('crossrefs-of-a-kind'))
         end
      )
      -- Don't process crossrefs in cross-ref-groups again.
      return span, false
   end
end

---@type Filter
return {
   -- Reader functionality. This only works if the input format is Pandoc's
   -- Markdown, though support for other input formats could be added in the future
   -- (such as LaTeX or DOCX).
   {
      Table = parse_table_attr,
      Inlines = parse_equation_attr,
   },
   {
      Span = remove_temp_classes,
   },
   {
      Inlines = parse_crossrefs,
   },
   -- Writer functionality. Currently only covers HTML output, though support for
   -- other formats will be added soon.
   {
      -- Number cross-referenceable elements and construct table with Ids and numbers.
      traverse = 'topdown', -- needed for subfigs
      Pandoc = number_sections,
      Span = number_equations,
      Figure = number_fig_or_tbl,
      Table = number_fig_or_tbl,
   },
   {
      traverse = 'topdown',
      Span = write_crossrefs,
   },
}
