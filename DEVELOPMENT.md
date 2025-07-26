# Testing

To run tests, the same version of Lua that pandoc is using should be used to install the required packages. At the time of writing, this is Lua 5.4.7. If your distribution does not offer this version, you can install it as follows:
```console
cd /tmp
curl -R -O https://www.lua.org/ftp/lua-5.4.7.tar.gz
tar zxf lua-5.4.7.tar.gz
cd lua-5.4.7
make linux
sudo make install
```
This will also install the Lua header files, which might otherwise need to be installed separately on your distribution.
You will also need `luarocks`, which, if the above installation method was used, can be installed as follows:
```console
cd /tmp
git clone https://github.com/luarocks/luarocks.git
cd luarocks
./configure --lua-version=5.4 \
            --with-lua=/usr/local \
            --prefix=/usr/local
make
sudo make install
```
You will also need to ensure that your `pandoc` binary supports [dynamic loading of C libraries](https://github.com/jgm/pandoc/issues/6850). To verify this, run `ldd $(which pandoc)`, and if the output is `not a dynamic executable` rather than a list of shared libraries, dynamic loading of C libraries is not supported. See also [pandoc's documentation on installation](https://pandoc.org/installing.html#linux).

## Install `busted` and `luacov`

```console
luarocks config local_by_default true
luarocks install busted
luarocks install luacov
luarocks install cluacov
```

## Run tests

```console
pandoc lua tests/unit.lua
```

## Generating an HTML report

Ensure the location of the Luacov binary location (`~/.luarocks/bin`) is on your `PATH`. To generate an HTML coverage report after running tests, run
```console
luacov -r html lib
```
Note that the output HTML file may have the `out` file extension rather than `html`.


# Pre-commit hooks

[pre-commit](https://pre-commit.com/) is used to manage git hooks. To install the pre-commit hooks, run `pre-commit install`. Note that running the hooks requires [`stylua`](https://github.com/JohnnyMorganz/StyLua), [`luacheck`](https://github.com/lunarmodules/luacheck), and [`lua-language-server`](https://github.com/LuaLS/lua-language-server) to be installed. Tests are also run in a pre-commit hook.
