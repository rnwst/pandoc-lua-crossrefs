local M = {}

---Check if AST element is a cross-reference (a cross-reference is a Span with class 'cross-ref').
---@param inline Inline
---@return boolean
M._is_crossref = function(inline)
   local is_crossref_link = inline and inline.tag == 'Link' and inline.attributes['reference-type'] ~= nil
   return is_crossref_link
end

---Check if AST element is a cross-reference group (a Span with class 'cross-ref-group').
---@param inline Inline
---@return boolean
M._is_crossref_group = function(inline)
   return inline and inline.tag == 'Span' and inline.classes:includes('cross-ref-group')
end

---Parse a cross-reference in Pandoc's Markdown.
---@param str Str
---@return Inline[] | nil
M._parse_crossref = function(str)
   local opening_bracket, prefix_suppressor, id, closing_bracket1, punctuation, closing_bracket2 =
      str.text:match('^(%[?)(%-?)#([%a%d-_:%.]-)(%]?)([\\%.!:?,;)]-)(%]?)$')
   if not id or id == '' then return end
   local only_internal_punctuation = id:find('^[%a%d]+[-_:%.]*[%a%d]+$') or id:find('^[%a%d]+$')
   if not only_internal_punctuation then return end
   if #closing_bracket1 ~= 0 and #closing_bracket2 ~= 0 then return end

   local crossref = pandoc.Link({}, '#' .. id, '', pandoc.Attr('', {}, { ['reference-type'] = 'ref+label' }))
   if prefix_suppressor == '-' then crossref.attributes['reference-type'] = 'ref' end
   local elts = pandoc.List { crossref }
   if opening_bracket == '[' then elts:insert(1, pandoc.Str('[')) end
   if closing_bracket1 == ']' then elts:insert(pandoc.Str(']')) end
   if punctuation ~= '' then elts:insert(pandoc.Str(punctuation)) end
   if closing_bracket2 == ']' then elts:insert(pandoc.Str(']')) end

   return elts
end

---Parse cross-references in Inlines.
---@param inlines Inlines
---@return (Inline[] | Inlines | nil), boolean?
M.parse_crossrefs = function(inlines)
   -- Parse cross-references into Links.
   local new_inlines = inlines:walk { Str = M._parse_crossref }

   -- Early return if no cross-references were found!
   if new_inlines == inlines then return end

   inlines = new_inlines

   -- Now separate out any opening or closing brackets in Strs into separate
   -- Strs, in case crossref groups don't begin and end with cross-references.
   inlines = inlines:walk {
      Str = function(str)
         if str.text:find('^%[.') then
            return { pandoc.Str('['), pandoc.Str(str.text:sub(2)) }
         elseif str.text:find('.%]$') then
            return { pandoc.Str(str.text:sub(1, -2)), pandoc.Str(']') }
         end
      end,
   }

   -- Now create crossref groups. Crossref Groups are represented by Spans of
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
               if M._is_crossref(elt) then at_least_one_crossref = true end
               group_content:insert(inlines[j])
            end
            j = j + 1
            if M._is_crossref(elt) and inlines[j] and inlines[j].tag == 'Str' then
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
            new_inlines:insert(inlines[i])
         end
      else
         new_inlines:insert(inlines[i])
      end
      i = i + 1
   end

   return new_inlines, false -- Nested cross-references are not allowed!
end

---Separate adjacent elements of a certain kind with commas, and the last two
---elements with ", and ". If there are only two adjacent elements, insert " and "
---between them.
---@param inlines Inlines | Inline[]
---@param matches fun(elt: Inline): boolean
M._insert_separators = function(inlines, matches)
   ---@type List<integer>
   local adjacent_indices = pandoc.List {}
   for i = 2, #inlines do
      if matches(inlines[i]) and matches(inlines[i - 1]) then adjacent_indices:insert(i) end
   end

   if #adjacent_indices == 1 then
      inlines:insert(adjacent_indices[1], pandoc.Str(' and '))
   elseif #adjacent_indices > 1 then
      inlines:insert(adjacent_indices[#adjacent_indices], pandoc.Str(', and '))
      -- Traverse list in reverse to avoid problems with changing indices.
      for i = #adjacent_indices - 1, 1, -1 do
         inlines:insert(adjacent_indices[i], pandoc.Str(', '))
      end
   end
end

---Get cross-reference target
---@param crossref Link
---@return { type: 'eqn'|'fig'|'sec'|'tbl', number: string }
M._get_target = function(crossref) return IDs[crossref.target:sub(2)] end

---Get type of cross-reference target.
---@param crossref Link
---@return string
M._get_target_type = function(crossref)
   local target = M._get_target(crossref)
   return target and target.type
end

---Whether element is a resolved cross-reference.
---@param elt Inline
---@return boolean
M._is_resolved_crossref = function(elt) return elt.tag == 'Link' and elt.classes:includes('cross-ref') end

---Resolve cross-reference.
---@param crossref         Link     cross-reference
---@param suppress_prefix? boolean  whether to suppress prefixing the referenced object's type (e.g. 'Fig.' or 'Tbl.')
---@return Link
M._resolve_crossref = function(crossref, suppress_prefix)
   local target = M._get_target(crossref)
   local crossref_text = ''
   if target ~= nil then
      if crossref.attributes['reference-type'] == 'ref+label' and not suppress_prefix then
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
      pandoc.log.warn('Cross-referenced element with id ' .. tostring(crossref.target) .. ' could not be resolved.')
   end
   local link = pandoc.Link(crossref_text, crossref.target)
   link.attr = pandoc.Attr('', { 'cross-ref' })
   return link
end

---Resolve single cross-references.
---@param link Link
---@return Link?
M.write_crossref = function(link)
   if M._is_crossref(link) then return M._resolve_crossref(link) end
end

---Resolve cross-references.
---@param span Span
---@return (Link | Span), false? | nil
M.write_crossrefs = function(span)
   if M._is_crossref_group(span) then
      local inlines = span.content

      -- Special case: If a cross-ref group is made up of a single Str, followed
      -- by a Space, followed by a cross-ref with suppressed prefix, treat this
      -- as a cross-ref with a custom prefix.
      if
         #inlines == 3
         and inlines[1].tag == 'Str'
         and inlines[2].tag == 'Space'
         and M._is_crossref(inlines[3])
         and inlines[3].attributes['reference-type'] ~= 'ref+label'
      then
         ---@cast inlines[3] Span
         local resolved_crossref = M._resolve_crossref(inlines[3])
         resolved_crossref.content = pandoc.List { inlines[1], inlines[2] } .. resolved_crossref.content
         return resolved_crossref
      end

      local i = 0
      while i < #inlines do
         i = i + 1
         if M._is_crossref(inlines[i]) then
            local crossref = inlines[i]
            ---@cast crossref Link
            local target_type = M._get_target_type(crossref)
            if not target_type then
               inlines[i] = M._resolve_crossref(crossref)
               goto continue
            end
            ---@type List<integer>
            local crossref_indices = pandoc.List { i }
            local j = i
            ---@type boolean
            local found_different_target_type = false
            while not found_different_target_type and j < #inlines do
               j = j + 1
               if M._is_crossref(inlines[j]) then
                  local next_crossref = inlines[j]
                  ---@cast next_crossref Link
                  if M._get_target_type(next_crossref) == target_type then
                     crossref_indices:insert(j)
                  else
                     found_different_target_type = true
                  end
               end
            end
            -- First resolve crossrefs, then insert separators.
            if #crossref_indices == 1 then
               inlines[crossref_indices[1]] = M._resolve_crossref(inlines[crossref_indices[1]] --[[@as Link]])
            else
               for _, idx in ipairs(crossref_indices) do
                  inlines[idx] = M._resolve_crossref(inlines[idx] --[[@as Link]], true)
               end
               local crossrefs_of_a_kind = pandoc.Span(
                  { table.unpack(inlines, crossref_indices:at(1), crossref_indices:at(-1)) },
                  pandoc.Attr('', { 'crossrefs-of-a-kind' })
               )
               crossrefs_of_a_kind.content:insert(1, pandoc.Space())
               local prefix = ''
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

               M._insert_separators(crossrefs_of_a_kind.content, M._is_resolved_crossref)

               for _ = crossref_indices:at(1), crossref_indices:at(-1) do
                  table.remove(inlines, crossref_indices[1])
               end
               inlines:insert(crossref_indices[1], crossrefs_of_a_kind)
            end
         end
         ::continue::
      end
      -- If there are any adjacent resolved cross-refs, they also need separators between them.
      M._insert_separators(
         inlines,
         function(elt)
            return M._is_resolved_crossref(elt) or (elt.tag == 'Span' and elt.classes:includes('crossrefs-of-a-kind'))
         end
      )
      -- Don't process crossrefs in cross-ref-groups again.
      return span, false
   end ---@diagnostic disable-line: missing-return
end

return M
