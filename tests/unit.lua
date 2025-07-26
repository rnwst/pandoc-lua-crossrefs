-- Unfortunately, LuaCATS annotations for busted are missing some `assert` fields.
---@diagnostic disable: undefined-field

-- Luacov (for coverage analysis) is installed locally, as there currently is no Arch package available.
-- The local location needs to be added to the search path.
local home = os.getenv('HOME')
package.path = home
   .. '/.luarocks/share/lua/5.4/?.lua;'
   .. home
   .. '/.luarocks/share/lua/5.4/?/init.lua;'
   .. package.path
package.cpath = home .. '/.luarocks/lib/lua/5.4/?.so;' .. package.cpath
require('busted.runner')()

describe('lib.utils', function()
   local utils = require('lib.utils')

   describe('html_escape', function()
      it(
         'escapes string to be used in HTML',
         function()
            assert.are.equals(
               '&lt;p onclick=&quot;alert(&#39;💥&#39;)&quot;&gt;Click me?&lt;/p&gt; &amp; &lt;3',
               utils.html_escape('<p onclick="alert(\'💥\')">Click me?</p> & <3')
            )
         end
      )
   end)

   describe('is_display_math', function()
      it(
         'says DisplayMath Math is display math',
         function() assert.are.equals(true, utils.is_display_math(pandoc.Math('DisplayMath', 'E=mc^2'))) end
      )
      it(
         'says not DisplayMath Math is not display math',
         function() assert.are.equals(false, utils.is_display_math(pandoc.Math('InlineMath', 'E=mc^2'))) end
      )
   end)
end)

describe('lib.parse_attr', function()
   local parse_attr = require('lib/parse-attr')

   describe('parse_table_attr', function()
      local function create_dummy_table(caption_str)
         local caption = pandoc.Caption(caption_str)
         return pandoc.Table(caption, {}, pandoc.TableHead {}, {
            attr = {},
            body = {},
            head = {},
            row_head_columns = 0,
         }, pandoc.TableFoot {})
      end

      it('parses Table Attr', function()
         local tbl = create_dummy_table('A caption. {#id .class key=val}')
         local parsed_tbl = parse_attr.parse_table_attr(tbl)
         ---@cast parsed_tbl Table
         assert.are.equals(pandoc.Attr('id', { 'class' }, { key = 'val' }), parsed_tbl.attr)
         assert.are.equals('A caption.', pandoc.utils.stringify(parsed_tbl.caption.long))
      end)

      it('parses Table Attr when caption is long', function()
         local caption = 'A ' .. ('very '):rep(42) .. 'loooooooooooong caption.'
         local tbl = create_dummy_table(caption .. ' {#id .class key=val}')
         local parsed_tbl = parse_attr.parse_table_attr(tbl)
         ---@cast parsed_tbl Table
         assert.are.equals(pandoc.Attr('id', { 'class' }, { key = 'val' }), parsed_tbl.attr)
         assert.are.equals(caption, pandoc.utils.stringify(parsed_tbl.caption.long))
      end)

      it('parses Table Attr when caption is otherwise empty', function()
         local tbl = create_dummy_table('{#id .class key=val}')
         local parsed_tbl = parse_attr.parse_table_attr(tbl)
         ---@cast parsed_tbl Table
         assert.are.equals(pandoc.Attr('id', { 'class' }, { key = 'val' }), parsed_tbl.attr)
         assert.are.equals(pandoc.Blocks {}, parsed_tbl.caption.long)
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
         assert.are.equals(expected_inlines, inlines)
      end)

      it('wraps DisplayMath without Attr in Span', function()
         local md_equation_with_attr = '$$E=mc^2$$'
         local expected_inlines = pandoc.Inlines { pandoc.Span(pandoc.Math('DisplayMath', 'E=mc^2')) }
         local doc = pandoc.read(md_equation_with_attr, 'markdown')
         local inlines = doc:walk({ Inlines = parse_attr.parse_equation_attr })
            :walk({ Span = parse_attr.remove_temp_classes }).blocks[1].content
         assert.are.equals(expected_inlines, inlines)
      end)

      it('wraps DisplayMath with malformed Attr in Span', function()
         local md_equation_with_attr = '$$E=mc^2$${#id' -- note the lack of a closing brace!
         local expected_inlines =
            pandoc.Inlines { pandoc.Span(pandoc.Math('DisplayMath', 'E=mc^2')), pandoc.Str('{#id') }
         local doc = pandoc.read(md_equation_with_attr, 'markdown')
         local inlines = doc:walk({ Inlines = parse_attr.parse_equation_attr })
            :walk({ Span = parse_attr.remove_temp_classes }).blocks[1].content
         assert.are.equals(expected_inlines, inlines)
      end)
   end)
end)
