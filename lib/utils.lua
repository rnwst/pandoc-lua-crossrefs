local utils = {}

---@type List<string>
utils.html_formats = pandoc.List {
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
utils.html_escape = function(str)
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
utils.is_display_math = function(inline) return inline.tag == 'Math' and inline.mathtype == 'DisplayMath' end

return utils
