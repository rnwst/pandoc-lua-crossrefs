local numbering = require('lib/numbering')

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

local function create_dummy_figure(caption_str)
   return pandoc.Figure(pandoc.Plain(pandoc.Image('alt text', 'test.jpg')), pandoc.Caption(caption_str))
end

describe('number_sections', function()
   _G.IDs = {}
   local header_doc = pandoc.Pandoc {
      pandoc.Header(2, { 'Header 1' }),
      pandoc.Header(3, { 'Header 2' }),
      pandoc.Header(3, { 'Header 3' }, pandoc.Attr('', { 'unnumbered' })),
      pandoc.Header(4, { 'Header 4' }),
   }
   local function get_header_numbers(doc)
      local header_numbers = pandoc.List {}
      doc:walk {
         ---@param header Header
         Header = function(header)
            if
               header.content
               and header.content[1].tag == 'Span'
               and header.content[1].classes:includes('header-section-number')
            then
               header_numbers:insert(pandoc.utils.stringify(header.content[1]))
            else
               header_numbers:insert('unnumbered')
            end
         end,
      }
      return header_numbers
   end

   it("doesn't number sections when `--number-sections` is specified", function()
      _G.PANDOC_WRITER_OPTIONS = pandoc.WriterOptions { number_sections = true }
      assert.equal(header_doc, numbering.number_sections(header_doc))
   end)

   it('numbers sections when `--number-sections` is not specified', function()
      _G.PANDOC_WRITER_OPTIONS = pandoc.WriterOptions {}
      assert.are.same({ '1', '1.1', 'unnumbered', '1.1.1' }, get_header_numbers(numbering.number_sections(header_doc)))
      _G.PANDOC_WRITER_OPTIONS = pandoc.WriterOptions { number_offset = { 1, 1 } }
      assert.are.same(
         { '1.2', '1.2.1', 'unnumbered', '1.2.1.1' },
         get_header_numbers(numbering.number_sections(header_doc))
      )
   end)
end)

describe('number_equations', function()
   local display_math = pandoc.Math('DisplayMath', 'E=mc^2')
   local equation = pandoc.Span(display_math, pandoc.Attr('id'))
   local unnumbered_equation = pandoc.Span(display_math, pandoc.Attr('id', { 'unnumbered' }))
   _G.IDs = {}

   it("temporarily doesn't number equations for DOCX output", function()
      _G.FORMAT = 'docx'
      assert.equal(display_math, numbering.number_equations(equation))
   end)

   it('numbers equation', function()
      _G.FORMAT = 'html'
      local result = numbering.number_equations(equation)
      ---@cast result Span
      assert.equal('Span', result.tag)
      assert.is_true(result.content:at(-1).classes:includes('display-math-label'))
   end)

   it("doesn't number unnumbered equation", function()
      _G.FORMAT = 'html'
      _G.PANDOC_WRITER_OPTIONS = pandoc.WriterOptions { html_math_method = 'katex' }
      local result = numbering.number_equations(unnumbered_equation)
      ---@cast result RawInline
      assert.equal('RawInline', result.tag)
   end)
end)

describe('number_fig_or_tbl', function()
   it('numbers Figure', function()
      local fig = create_dummy_figure('Figure caption')
      local passed_fig = numbering.number_fig_or_tbl(fig)
      ---@cast passed_fig Figure
      local caption = passed_fig.caption.long
      assert.is_true(#caption > 0)
      assert.equal('Span', caption[1].content[1].tag)
      local fig_number = caption[1].content[1]
      ---@cast fig_number Span
      assert.is_not_nil(pandoc.utils.stringify(fig_number.content):find('^Fig%.\u{A0}'))
   end)

   it('numbers Table', function()
      local tbl = create_dummy_table('Table caption')
      local passed_tbl = numbering.number_fig_or_tbl(tbl)
      ---@cast passed_tbl Table
      local caption = passed_tbl.caption.long
      assert.is_true(#caption > 0)
      assert.equal('Span', caption[1].content[1].tag)
      local tbl_number = caption[1].content[1]
      ---@cast tbl_number Span
      assert.is_not_nil(pandoc.utils.stringify(tbl_number.content):find('^Tbl%.\u{A0}'))
   end)

   it('numbers Table with empty Caption', function()
      local tbl = create_dummy_table()
      local passed_tbl = numbering.number_fig_or_tbl(tbl)
      ---@cast passed_tbl Table
      local caption = passed_tbl.caption.long
      assert.is_true(#caption > 0)
      assert.equal('Span', caption[1].content[1].tag)
      local tbl_number = caption[1].content[1]
      ---@cast tbl_number Span
      assert.is_not_nil(pandoc.utils.stringify(tbl_number.content):find('^Tbl%.\u{A0}'))
   end)

   it('numbers Figure with empty Caption', function()
      local fig = create_dummy_figure()
      local passed_fig = numbering.number_fig_or_tbl(fig)
      ---@cast passed_fig Table
      local caption = passed_fig.caption.long
      assert.is_true(#caption > 0)
      assert.equal('Span', caption[1].content[1].tag)
      local fig_number = caption[1].content[1]
      ---@cast fig_number Span
      assert.is_not_nil(pandoc.utils.stringify(fig_number.content):find('^Fig%.\u{A0}'))
   end)

   it('numbers subfigures', function()
      local subfigs = pandoc.Figure({
         create_dummy_figure('Subfig 1'),
         create_dummy_figure('Subfig 2'),
         create_dummy_figure('Subfig 3'),
      }, pandoc.Caption('Subfigures'))
      local numbered_subfigs = numbering.number_fig_or_tbl(subfigs)
      ---@cast numbered_subfigs Figure
      local first_subfig_number = numbered_subfigs.content[1].caption.long[1].content[1]
      ---@cast first_subfig_number Span
      assert.equal(pandoc.utils.stringify(first_subfig_number), '(a)')
   end)

   it("doesn't number unnumbered Figures or Tables", function()
      local fig = create_dummy_figure('Figure caption')
      fig.classes:insert('unnumbered')
      local tbl = create_dummy_table('Table caption')
      tbl.classes:insert('unnumbered')
      assert.is_nil(numbering.number_fig_or_tbl(fig))
      assert.is_nil(numbering.number_fig_or_tbl(tbl))
   end)

   it("doesn't number unnumbered Figures or Tables with empty Captions", function()
      local fig = create_dummy_figure()
      fig.classes:insert('unnumbered')
      local tbl = create_dummy_table()
      tbl.classes:insert('unnumbered')
      assert.is_nil(numbering.number_fig_or_tbl(fig))
      assert.is_nil(numbering.number_fig_or_tbl(tbl))
   end)
end)
