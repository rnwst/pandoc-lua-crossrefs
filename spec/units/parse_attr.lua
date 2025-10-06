local parse_attr = require('lib/parse-attr')

-- Test utils
local function create_dummy_table(caption_str)
   local caption = pandoc.Caption(caption_str)
   return pandoc.Table(caption, {}, pandoc.TableHead {}, {
      attr = {},
      body = {},
      head = {},
      row_head_columns = 0,
   }, pandoc.TableFoot {})
end

describe('parse_table_attr', function()
   it('parses Table Attr', function()
      local tbl = create_dummy_table('A caption. {#id .class key=val}')
      local parsed_tbl = parse_attr.parse_table_attr(tbl)
      ---@cast parsed_tbl Table
      assert.equal(pandoc.Attr('id', { 'class' }, { key = 'val' }), parsed_tbl.attr)
      assert.equal('A caption.', pandoc.utils.stringify(parsed_tbl.caption.long))
   end)

   it('parses Table Attr when caption is long', function()
      local caption = 'A ' .. ('very '):rep(42) .. 'loooooooooooong caption.'
      local tbl = create_dummy_table(caption .. ' {#id .class key=val}')
      local parsed_tbl = parse_attr.parse_table_attr(tbl)
      ---@cast parsed_tbl Table
      assert.equal(pandoc.Attr('id', { 'class' }, { key = 'val' }), parsed_tbl.attr)
      assert.equal(caption, pandoc.utils.stringify(parsed_tbl.caption.long))
   end)

   it('parses Table Attr when caption is otherwise empty', function()
      local tbl = create_dummy_table('{#id .class key=val}')
      local parsed_tbl = parse_attr.parse_table_attr(tbl)
      ---@cast parsed_tbl Table
      assert.equal(pandoc.Attr('id', { 'class' }, { key = 'val' }), parsed_tbl.attr)
      assert.equal(pandoc.Blocks {}, parsed_tbl.caption.long)
   end)

   it("doesn't apply Attr when it is empty (to avoid overwriting existing Attr)", function()
      local tbl = create_dummy_table('Caption without Attr.')
      -- The Id might have been set programmatically by a filter, and we
      -- shouldn't overwrite it!
      tbl.identifier = 'my-id'
      local parsed_tbl = parse_attr.parse_table_attr(tbl)
      assert.equal(parsed_tbl.identifier, 'my-id') ---@diagnostic disable-line: need-check-nil
   end)
end)

describe('parse_equation_attr and remove_temp_classes', function()
   it('parses DisplayMath Attr from Markdown input', function()
      local md_equation_with_attr = '$$E=mc^2$${#id .unnumbered key=val}'
      local expected_inlines = pandoc.Inlines {
         pandoc.Span(pandoc.Math('DisplayMath', 'E=mc^2'), pandoc.Attr('id', { 'unnumbered' }, { key = 'val' })),
      }
      local inlines = parse_attr.parse_equation_attr(
         pandoc.read(md_equation_with_attr, 'markdown').blocks[1].content --[[@as Inlines]]
      )
      assert.equal(expected_inlines, inlines)
   end)

   it('wraps DisplayMath without Attr in Span', function()
      local md_equation_with_attr = '$$E=mc^2$$'
      local expected_inlines = pandoc.Inlines { pandoc.Span(pandoc.Math('DisplayMath', 'E=mc^2')) }
      local doc = pandoc.read(md_equation_with_attr, 'markdown')
      local inlines = doc:walk({ Inlines = parse_attr.parse_equation_attr })
         :walk({ Span = parse_attr.remove_temp_classes }).blocks[1].content
      assert.equal(expected_inlines, inlines)
   end)

   it('wraps DisplayMath with malformed Attr in Span', function()
      local md_equation_with_attr = '$$E=mc^2$${#id' -- note the lack of a closing brace!
      local expected_inlines = pandoc.Inlines { pandoc.Span(pandoc.Math('DisplayMath', 'E=mc^2')), pandoc.Str('{#id') }
      local doc = pandoc.read(md_equation_with_attr, 'markdown')
      local inlines = doc:walk({ Inlines = parse_attr.parse_equation_attr })
         :walk({ Span = parse_attr.remove_temp_classes }).blocks[1].content
      assert.equal(expected_inlines, inlines)
   end)
end)
