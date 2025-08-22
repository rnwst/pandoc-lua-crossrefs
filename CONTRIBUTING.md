# Contributing to pandoc-lua-crossrefs

Welcome to pandoc-lua-crossrefs! Thank you for contributing to this project.

Before submitting a pull request, make sure to [run tests](#testing) and to install [pre-commit hooks](#pre-commit-hooks). See also the [commit message guidelines](#commit-message-guidelines). If you have added new functionality, ensure that code coverage remains at 100% by also adding corresponding tests (see [Generating an HTML report](#generating-an-html-report) for how to measure coverage). Test coverage is checked as part of the [pre-commit hooks](#pre-commit-hooks).

## Testing

To run tests, the same version of Lua that pandoc is using should be used to install the required packages. At the time of writing, this is Lua 5.4.7. If your distribution does not provide this version in the official repositories, you can install it as follows:
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
You will also need to ensure that your `pandoc` binary supports [dynamic loading of C libraries](https://github.com/jgm/pandoc/issues/6850). To verify this, run `ldd $(which pandoc)`, and if the output is `not a dynamic executable` rather than a list of shared libraries, *dynamic loading of C libraries is not supported*. See also [pandoc's documentation on installation](https://pandoc.org/installing.html#linux).

### Install `busted` and `luacov`

```console
luarocks config local_by_default true
luarocks install busted
luarocks install luacov
luarocks install cluacov
luarocks install ansicolors
```

### Run tests

```console
./test.lua
```
You can pass [busted CLI options](https://lunarmodules.github.io/busted/#usage) to `test.lua`. E.g. to only run unit tests,
```console
./test.lua spec/units
```
or to run a single golden test:
```console
./test.lua --tags=latex2html
```
In addition to busted's CLI options, another option has been implemented, `--accept`. Passing this flag to `test.lua` results in the golden test's expected outputs being overwritten with pandoc's actual output.

### Generating an HTML report

Ensure the location of the Luacov binary location (`~/.luarocks/bin`) is on your `PATH`. To generate an HTML coverage report after running tests, run
```console
luacov
```
The HTML report provides test coverage information, including which lines of code are not currently covered. This project aims to achieve 100% test coverage. To verify that this is the case, run
```console
./ci-coverage.lua
```


## Pre-commit hooks

[pre-commit](https://pre-commit.com/) is used to manage git hooks. To install the pre-commit hooks, run `pre-commit install`. Note that running the hooks requires [`stylua`](https://github.com/JohnnyMorganz/StyLua), [`luacheck`](https://github.com/lunarmodules/luacheck), and [`lua-language-server`](https://github.com/LuaLS/lua-language-server) to be installed. Tests are also run in a pre-commit hook, and test coverage is checked (which must be 100%).


## Commit message guidelines

This project uses [git's suggested commit message guidelines](https://git-scm.com/book/en/v2/Distributed-Git-Contributing-to-a-Project). Note that there are currently no automated checks in place for these commit message guidelines, so it is down to the commit author to observe them.

Commit messages should have a headline and a body (unless the change is trivial, in which case just a headline suffices). Lines should be wrapped to 72 characters. The headline should be even shorter, if at all possible. It should start with a capitalized word, and should not end with punctuation. Write all information about applied changes in the imperative (i.e. "Fix bug", not "Fixed bug"). Information about previous behaviour should be written in the past tense (i.e. "Previously we did this. Do that instead."). Bullet points in the body are fine.
