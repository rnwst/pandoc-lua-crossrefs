local say = require('say')
local dmp = require('spec.helpers.diff_match_patch')
local colors = require('ansicolors')

---Split a given string into lines.
---@param str string
---@return List<string>
local function split_lines(str)
   local lines = pandoc.List {}
   local pos = 1

   while true do
      local start, finish = str:find('\r?\n', pos)
      if not start then
         -- Add the remaining text (could be empty).
         lines:insert(string.sub(str, pos))
         break
      end
      lines:insert(string.sub(str, pos, start - 1))
      pos = finish + 1
   end

   return lines
end

---@param expected string
---@param received string
---@return string
local function diff_strings(expected, received)
   local diffs = dmp.diff_main(expected, received)
   ---@cast diffs [integer, string][]
   dmp.diff_cleanupSemantic(diffs)
   local colored_diffs = pandoc.List {}
   for i, d in ipairs(diffs) do
      local op, text = d[1], d[2]
      text = text:gsub('\n', '⏎\n') -- make newlines visible
      if op == dmp.DIFF_INSERT then
         colored_diffs:insert(colors('%{bright green reverse}' .. text .. '%{reset}'))
      elseif op == dmp.DIFF_DELETE then
         colored_diffs:insert(colors('%{bright red reverse}' .. text .. '%{reset}'))
      else
         -- We're not so interested in the text that is the same, so we
         -- only print the first two and last two lines.
         local lines = split_lines(text)
         if #lines >= 6 then
            for _ = 3, #lines - 4 do
               lines:remove(3)
            end
            lines[3] = '⋮'
            if i == 1 then
               lines:remove(1)
               lines:remove(1)
            elseif i == #diffs then
               if lines:at(-1) == '' then lines:remove() end
               lines:remove()
               lines:remove()
            end
            text = table.concat(lines, '\n')
         end
         colored_diffs:insert(text)
      end
   end
   return colors('\n%{underline magenta}Diff of expected and received:\n') .. table.concat(colored_diffs)
end

---Adapted from luassert's own `equals` assertion.
local function strings_equal(state, arguments, level)
   level = (level or 1) + 1
   local argcnt = arguments.n
   assert(argcnt > 1, say('assertion.internal.argtolittle', { 'equals', 2, tostring(argcnt) }), level)
   local result = arguments[1] == arguments[2]
   if not result then state.failure_message = diff_strings(arguments[1], arguments[2]) end
   return result
end

return strings_equal
