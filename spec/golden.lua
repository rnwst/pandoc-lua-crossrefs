local strings_equal = require('spec.helpers.strings_equal')

-- Register custom assertion.
assert:register('assertion', 'strings_equal', strings_equal, '', '')

local base_dir = 'spec/golden/'
-- See https://github.com/jgm/pandoc/issues/11032
local tests = pandoc.List(pandoc.system.list_directory(base_dir))
tests = tests:map(function(dir) return pandoc.path.join { base_dir, dir } end)
for _, test in ipairs(tests) do
   if not test:find('%.disabled$') then
      -- Tag tests by subdirectory.
      it(test .. ' #' .. pandoc.path.filename(test), function()
         local files = pandoc.List(pandoc.system.list_directory(test))
         local input_file =
            pandoc.path.join { test, ({ files:find_if(function(file) return file:find('^input%.') end) })[1] }
         local defaults_file = files:includes('defaults.yaml') and pandoc.path.join { test, 'defaults.yaml' }
         local expected_file =
            pandoc.path.join { test, ({ files:find_if(function(file) return file:find('^expected%.') end) })[1] }
         local expected = ({ pandoc.mediabag.fetch(expected_file) })[2]
         local args = pandoc.List { '--output=' .. expected_file, input_file }
         if defaults_file then args:insert(1, '--defaults=' .. defaults_file) end
         pandoc.pipe('pandoc', args, '')
         local received = ({ pandoc.mediabag.fetch(expected_file) })[2]
         if not _G.ACCEPT_TEST_RESULTS then
            -- Restore previous version of expected output file.
            io.open(expected_file, 'w'):write(expected):close()
            -- Compare expected output with actual output.
            assert.strings_equal(expected, received) ---@diagnostic disable-line: undefined-field
         end
      end)
   end
end
