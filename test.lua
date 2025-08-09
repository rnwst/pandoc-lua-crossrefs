#!/usr/bin/env -S pandoc lua

-- Luacov (for coverage analysis) is installed locally, as there currently is no Arch package available.
-- The local location needs to be added to the search path.
local home = os.getenv('HOME')
package.path = home
   .. '/.luarocks/share/lua/5.4/?.lua;'
   .. home
   .. '/.luarocks/share/lua/5.4/?/init.lua;'
   .. package.path
package.cpath = home .. '/.luarocks/lib/lua/5.4/?.so;' .. package.cpath

-- Remove `--accept` option if passed so that busted doesn't complain.
arg = pandoc.List(arg):filter(function(arg) -- luacheck: ignore 121
   if arg == '--accept' then
      ACCEPT_TEST_RESULTS = true -- luacheck: ignore 111
      return false
   end
   return true
end)

require('busted.runner') { standalone = false }
