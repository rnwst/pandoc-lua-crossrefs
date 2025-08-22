local utils = require('lib.utils')

describe('html_escape', function()
   it(
      'escapes string to be used in HTML',
      function()
         assert.equal(
            '&lt;p onclick=&quot;alert(&#39;💥&#39;)&quot;&gt;Click me?&lt;/p&gt; &amp; &lt;3',
            utils.html_escape('<p onclick="alert(\'💥\')">Click me?</p> & <3')
         )
      end
   )
end)

describe('is_display_math', function()
   it(
      'says DisplayMath Math is display math',
      function() assert.equal(true, utils.is_display_math(pandoc.Math('DisplayMath', 'E=mc^2'))) end
   )
   it(
      'says not DisplayMath Math is not display math',
      function() assert.equal(false, utils.is_display_math(pandoc.Math('InlineMath', 'E=mc^2'))) end
   )
end)
