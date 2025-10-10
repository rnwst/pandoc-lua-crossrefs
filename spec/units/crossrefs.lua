local crossrefs = require('lib/crossrefs')

-- Test utils
local function create_crossref(id)
   return pandoc.Link({}, '#' .. id, '', pandoc.Attr('', {}, { ['reference-type'] = 'ref+label' }))
end

describe('_is_crossref', function()
   it("says Link with 'reference-type' attribute is a cross-reference", function()
      local link = pandoc.Link({}, '', '', pandoc.Attr('', {}, { ['reference-type'] = 'ref' }))
      assert.is_true(crossrefs._is_crossref(link))
   end)

   it("says Link without 'reference-type' attribute is not a cross-reference", function()
      local link = pandoc.Link({}, '', '', pandoc.Attr('', {}, {}))
      assert.is_false(crossrefs._is_crossref(link))
   end)
end)

describe('_is_crossref_group', function()
   it("says Span with class 'cross-ref-group' is a cross-reference group", function()
      local span = pandoc.Span({}, pandoc.Attr('', { 'cross-ref-group' }))
      assert.is_true(crossrefs._is_crossref_group(span))
   end)

   it("says Span without class 'cross-ref-group' is not a cross-reference group", function()
      local span = pandoc.Span {}
      assert.is_false(crossrefs._is_crossref_group(span))
   end)
end)

describe('_parse_crossref', function()
   it('parses simple cross-reference', function()
      local inlines = crossrefs._parse_crossref(pandoc.Str('#fig1'))
      assert.is_not_nil(inlines)
      assert.equal(1, #inlines)
      assert.equal('Link', inlines[1].tag) ---@diagnostic disable-line: need-check-nil
      assert.equal('#fig1', inlines[1].target) ---@diagnostic disable-line: need-check-nil
      assert.equal('ref+label', inlines[1].attributes['reference-type']) ---@diagnostic disable-line: need-check-nil
   end)

   it('parses cross-reference with opening bracket', function()
      local inlines = crossrefs._parse_crossref(pandoc.Str('[#sec'))
      assert.is_not_nil(inlines)
      assert.equal(2, #inlines)
      assert.equal(pandoc.Str('['), inlines[1]) ---@diagnostic disable-line: need-check-nil
   end)

   it('parses cross-reference with closing bracket', function()
      local inlines = crossrefs._parse_crossref(pandoc.Str('#sec]'))
      assert.is_not_nil(inlines)
      assert.equal(2, #inlines)
      assert.equal(pandoc.Str(']'), inlines[2]) ---@diagnostic disable-line: need-check-nil
   end)

   it('parses cross-reference with punctuation', function()
      local punctuation = { '.', ':', '?', '!', ';' }
      for _, p in ipairs(punctuation) do
         local inlines = crossrefs._parse_crossref(pandoc.Str('#sec' .. p))
         assert.is_not_nil(inlines)
         assert.equal(2, #inlines)
         assert.equal(pandoc.Str(p), inlines[2]) ---@diagnostic disable-line: need-check-nil
      end
   end)

   it('parses cross-reference with closing bracket before punctuation', function()
      local inlines = crossrefs._parse_crossref(pandoc.Str('#sec].'))
      assert.is_not_nil(inlines)
      assert.equal(3, #inlines)
      assert.equal(pandoc.Str(']'), inlines[2]) ---@diagnostic disable-line: need-check-nil
      assert.equal(pandoc.Str('.'), inlines[3]) ---@diagnostic disable-line: need-check-nil
   end)

   it('parses cross-reference with closing bracket after punctuation', function()
      local inlines = crossrefs._parse_crossref(pandoc.Str('#sec.]'))
      assert.is_not_nil(inlines)
      assert.equal(3, #inlines)
      assert.equal(pandoc.Str('.'), inlines[2]) ---@diagnostic disable-line: need-check-nil
      assert.equal(pandoc.Str(']'), inlines[3]) ---@diagnostic disable-line: need-check-nil
   end)

   it('parses cross-reference with multiple, non-adjacent internal punctuation', function()
      local inlines = crossrefs._parse_crossref(pandoc.Str('#fig:equal-heights'))
      assert.is_not_nil(inlines)
      assert.equal(1, #inlines)
      assert.equal('Link', inlines[1].tag) ---@diagnostic disable-line: need-check-nil
      assert.equal('#fig:equal-heights', inlines[1].target) ---@diagnostic disable-line: need-check-nil
   end)

   it('parses cross-reference in parentheses', function()
      local inlines = crossrefs._parse_crossref(pandoc.Str('(#fig1)'))
      assert.is_not_nil(inlines)
      assert.equal(3, #inlines)
      assert.equal('Str', inlines[1].tag) ---@diagnostic disable-line: need-check-nil
      assert.equal('Link', inlines[2].tag) ---@diagnostic disable-line: need-check-nil
      assert.equal('Str', inlines[3].tag) ---@diagnostic disable-line: need-check-nil
   end)

   it("doesn't parse invalid cross-references", function()
      -- Space in cross-reference
      assert.is_nil(crossrefs._parse_crossref(pandoc.Str('# fig1')))
      -- External punctuation.
      assert.is_nil(crossrefs._parse_crossref(pandoc.Str('#.fig')))
      -- Cross-reference without Id.
      assert.is_nil(crossrefs._parse_crossref(pandoc.Str('[-#].')))
      -- Cross-reference with two closing brackets.
      assert.is_nil(crossrefs._parse_crossref(pandoc.Str('#fig1].]')))
   end)
end)

describe('parse_crossrefs', function()
   it('parses single cross-reference', function()
      local md = '#fig1'
      local inlines = pandoc.read(md, 'markdown').blocks[1].content:walk { Inlines = crossrefs.parse_crossrefs }
      assert.equal(1, #inlines)
      assert.equal('Link', inlines[1].tag)
   end)

   it('parses cross-reference group', function()
      local md = '[#fig1; #fig2]'
      local inlines = pandoc.read(md, 'markdown').blocks[1].content:walk { Inlines = crossrefs.parse_crossrefs }
      ---@cast inlines Inline[]
      assert.equal(1, #inlines)
      assert.equal('Span', inlines[1].tag)
      assert.is_true(inlines[1].classes:includes('cross-ref-group'))
      assert.equal(2, #inlines[1].content)
      assert.is_true(crossrefs._is_crossref(inlines[1].content[1] --[[@as Inline]]))
      assert.is_true(crossrefs._is_crossref(inlines[1].content[2] --[[@as Inline]]))
   end)

   it("parses cross-reference group that doesn't begin and end with a cross-reference", function()
      local md = '[particularly #fig1 or #fig2 as well]'
      local inlines = pandoc.read(md, 'markdown').blocks[1].content:walk { Inlines = crossrefs.parse_crossrefs }
      ---@cast inlines Inline[]
      assert.equal(1, #inlines)
      assert.equal('Span', inlines[1].tag)
      assert.is_true(inlines[1].classes:includes('cross-ref-group'))
   end)

   it("doesn't change text that contains no cross-reference", function()
      local md = 'some text'
      local inlines = pandoc.read(md, 'markdown').blocks[1].content
      ---@cast inlines (Inline[] | Inlines)
      assert.is_nil(crossrefs.parse_crossrefs(inlines))
   end)

   it("doesn't parse group that contains no cross-reference", function()
      local md = 'See #fig1, [some text in brackets]'
      local inlines = pandoc.read(md, 'markdown').blocks[1].content
      ---@cast inlines (Inline[] | Inlines)
      local new_inlines = crossrefs.parse_crossrefs(inlines)
      -- Contains no cross-reference group.
      ---@diagnostic disable-next-line: need-check-nil
      assert.equal(0, #new_inlines:filter(function(elt) return elt.tag == 'Span' end))
      -- Contains cross-reference.
      ---@diagnostic disable-next-line: need-check-nil
      assert.equal(1, #new_inlines:filter(function(elt) return elt.tag == 'Link' end))
   end)

   it("doesn't parse empty group", function()
      local md = '[]'
      local inlines = pandoc.read(md, 'markdown').blocks[1].content
      local new_inlines = inlines:walk { Inlines = crossrefs.parse_crossrefs }
      assert.equal(inlines, new_inlines)
   end)

   it("doesn't get confused by multiple opening brackets", function()
      local md = 'See [text and [#fig2 and #fig3]'
      local inlines = pandoc.read(md, 'markdown').blocks[1].content
      local new_inlines = inlines:walk { Inlines = crossrefs.parse_crossrefs }
      ---@cast new_inlines (Inline[] | Inlines)
      assert.is_truthy(pandoc.write(pandoc.Pandoc(pandoc.Plain(new_inlines)), 'plain'):match('^See %[text and '))
      assert.equal('Span', new_inlines:at(-1).tag)
      assert.equal(1, #new_inlines:filter(function(elt) return crossrefs._is_crossref_group(elt) end))
   end)

   it('converts escaped semicolon in cross-reference goup', function()
      local md = '[#fig2\\; #fig3]'
      local inlines = pandoc
         .read(md, 'markdown-all_symbols_escapable').blocks[1].content
         :walk { Inlines = crossrefs.parse_crossrefs }
      assert.is_true(inlines[1].content:includes(pandoc.Str(';')))
   end)
end)

describe('_insert_separators', function()
   it('inserts separators', function()
      local str = pandoc.Str('foo')
      local matcher = function(elt) return elt.tag == 'Str' end
      local two_strs = pandoc.Inlines { str, str }
      crossrefs._insert_separators(two_strs, matcher)
      assert.equal(3, #two_strs)
      local three_strs = pandoc.Inlines { str, str, str }
      crossrefs._insert_separators(three_strs, matcher)
      assert.equal(5, #three_strs)
   end)
end)

describe('_get_target and _get_target_type', function()
   _G.IDs = { fig1 = { type = 'fig', number = '1' } }

   describe('_get_target', function()
      it(
         'retrieves target',
         function() assert.equal(_G.IDs['fig1'], crossrefs._get_target(create_crossref('fig1'))) end
      )
      it(
         'returns `nil` if target is not found',
         function() assert.is_nil(crossrefs._get_target(create_crossref('non-existent'))) end
      )
   end)

   describe('_get_target_type', function()
      it(
         'retrieves target type',
         function() assert.equal('fig', crossrefs._get_target_type(create_crossref('fig1'))) end
      )
   end)
end)

describe('_is_resolved_crossref', function()
   it('says resolved cross-reference is resolved', function()
      _G.FORMAT = 'html'
      local resolved_crossref = pandoc.Link({}, '#fig1', '', pandoc.Attr('', { 'cross-ref' }))
      assert.is_true(crossrefs._is_resolved_crossref(resolved_crossref))
   end)

   it('says resolved DOCX cross-reference is resolved', function()
      _G.FORMAT = 'docx'
      local resolved_crossref = pandoc.Span({}, pandoc.Attr('', { 'cross-ref' }))
      assert.is_true(crossrefs._is_resolved_crossref(resolved_crossref))
   end)
end)

describe('write_crossref', function()
   _G.IDs = {
      sec1 = { type = 'sec', number = '1' },
      fig1 = { type = 'fig', number = '1' },
      tbl1 = { type = 'tbl', number = '1' },
      eqn1 = { type = 'eqn', number = '1' },
   }
   _G.FORMAT = 'html'

   it('resolves cross-references', function()
      for id, _ in pairs(_G.IDs) do
         local unresolved_crossref = create_crossref(id)
         local resolved_crossref = crossrefs.write_crossref(unresolved_crossref)
         assert.equal('1', resolved_crossref.content[1].text:sub(-1)) ---@diagnostic disable-line: need-check-nil
      end
   end)

   it('print warning if cross-reference cannot be resolved', function()
      local log_stub = stub(_G.pandoc.log, 'warn')
      crossrefs.write_crossref(create_crossref('non-existent'))
      assert.stub(log_stub).was.called(1)
      log_stub:revert()
   end)

   it('resolves DOCX cross-reference', function()
      _G.FORMAT = 'docx'
      for id, _ in pairs(_G.IDs) do
         local unresolved_crossref = create_crossref(id)
         local resolved_crossref = crossrefs.write_crossref(unresolved_crossref)
         assert.equal('Span', resolved_crossref.tag) ---@diagnostic disable-line: need-check-nil
      end
   end)
end)

describe('write_crossrefs', function()
   _G.IDs = {
      sec1 = { type = 'sec', number = '1' },
      sec2 = { type = 'sec', number = '2' },
      fig1 = { type = 'fig', number = '1' },
      fig2 = { type = 'fig', number = '2' },
      tbl1 = { type = 'tbl', number = '1' },
      tbl2 = { type = 'tbl', number = '2' },
      eqn1 = { type = 'eqn', number = '1' },
      eqn2 = { type = 'eqn', number = '2' },
   }
   _G.FORMAT = 'html'

   it('writes cross-reference groups', function()
      for _, type in ipairs { 'sec', 'fig', 'tbl', 'eqn' } do
         local cross_ref_group = pandoc.Span(
            { create_crossref(type .. '1'), create_crossref(type .. '2') },
            pandoc.Attr('', { 'cross-ref-group' })
         )
         local resolved_crossrefs = crossrefs.write_crossrefs(cross_ref_group)
         assert.equal('1 and 2', pandoc.utils.stringify(resolved_crossrefs):sub(7))
      end
   end)

   it('special case: cross-reference group with single cross-reference with suppressed prefix', function()
      local crossref_without_prefix = create_crossref('fig1')
      crossref_without_prefix.attributes['reference-type'] = 'ref'
      local special_cross_ref_group = pandoc.Span(
         { pandoc.Str('Figure'), pandoc.Space(), crossref_without_prefix },
         pandoc.Attr('', { 'cross-ref-group' })
      )
      assert.equal('Figure 1', pandoc.utils.stringify(crossrefs.write_crossrefs(special_cross_ref_group)))
   end)

   it('handles non-resolvable cross-reference in group', function()
      local cross_ref_group = pandoc.Span({ create_crossref('non-existent') }, pandoc.Attr('', { 'cross-ref-group' }))
      local log_stub = stub(_G.pandoc.log, 'warn')
      local resolved_crossrefs = crossrefs.write_crossrefs(cross_ref_group)
      assert.equal('??', pandoc.utils.stringify(resolved_crossrefs))
      assert.stub(log_stub).was.called(1)
      log_stub:revert()
   end)

   it('handles cross-references of different types', function()
      local cross_ref_group =
         pandoc.Span({ create_crossref('sec1'), create_crossref('fig1') }, pandoc.Attr('', { 'cross-ref-group' }))
      local resolved_crossrefs = crossrefs.write_crossrefs(cross_ref_group)
      assert.equal('Sec. 1 and Fig. 1', pandoc.utils.stringify(resolved_crossrefs))
   end)
end)
