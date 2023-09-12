                                              __
                                             / /_  ____  ____
                                            / __ \/ __ \/ __ \
                                           / / / / /_/ / /_/ /
                                          /_/ /_/\____/ .___/
                                                     /_/
                                      · Neovim motions on speed! ·

<p align="center">
  <img src="https://img.shields.io/github/issues/smoka7/hop.nvim?color=cyan&style=for-the-badge"/>
  <img src="https://img.shields.io/github/issues-pr/smoka7/hop.nvim?color=green&style=for-the-badge"/>
  <img src="https://img.shields.io/github/contributors-anon/smoka7/hop.nvim?color=blue&style=for-the-badge"/>
  <img src="https://img.shields.io/github/last-commit/smoka7/hop.nvim?style=for-the-badge"/>
  <img src="https://img.shields.io/github/v/tag/smoka7/hop.nvim?color=pink&label=release&style=for-the-badge"/>
</p>

**Hop** is an [EasyMotion](https://github.com/easymotion/vim-easymotion)-like plugin allowing you to jump anywhere in a
document with as few keystrokes as possible. It does so by annotating text in
your buffer with hints, short string sequences for which each character
represents a key to type to jump to the annotated text. Most of the time,
those sequences’ lengths will be between 1 to 3 characters, making every jump
target in your document reachable in a few keystrokes.

<p align="center">
  <img src="https://user-images.githubusercontent.com/506592/176885253-5f618593-77c5-4843-9101-a9de30f0a022.png"/>
</p>

This is a fork of the [original hop.nvim repo](https://github.com/phaazon/hop.nvim)

# Features

- Go to any word in the current buffer (`:HopWord`).
- Go to any camelCase word in the current buffer (`:HopCamelCase`).
- Go to any character in the current buffer (`:HopChar1`).
- Go to any bigrams in the current buffer (`:HopChar2`).
- Make an arbitrary search akin to <kbd>/</kbd> and go to any occurrences (`:HopPattern`).
- Go to any line and any line start (`:HopLine`, `:HopLineStart`).
- Go to anywhere (`:HopAnywhere`).
- Go to treesitter nodes (`:HopNodes`).
- Paste text in the hinted position without jumping (`:HopPaste`).
- Yank the text between two hinted position without jumping (`:HopYankChar1`).
- Use Hop cross windows with multi-windows support (`:Hop*MW`).
- Use it with commands like `v`, `d`, `c`, `y` to visually select/delete/change/yank up to your new cursor position.
- Support a wide variety of user configuration options, among the possibility to alter the behavior of commands
  to hint only before or after the cursor (`:Hop*BC`, `:Hop*AC`), for the current line (`:Hop*CurrentLine`),
  change the dictionary keys to use for the labels, jump on sole occurrence, etc.
- Extensible: provide your own jump targets and create Hop extensions!

# Installation

## Using lazy.nvim

```lua
{
    'smoka7/hop.nvim',
    version = "*",
    opts = {},
}
```

## Using packer

```lua
use {
  'smoka7/hop.nvim',
  tag = '*', -- optional but strongly recommended
  config = function()
    -- you can configure Hop the way you like here; see :h hop-config
    require'hop'.setup { keys = 'etovxqpdygfblzhckisuran' }
  end
}
```

## Supported Neovim versions

Hop supports **latest stable release** and nightly releases of Neovim. However, keep in mind that if you are on a nightly version, you must be **on
the last one**. If you are not, then you are exposed to compatibility issues / breakage.

## Important note about versioning

This plugin implements [SemVer] via git tags. Versions are prefixed with a `v`. You are **advised** to use a major version
dependency to be sure your config will not break when Hop gets updated.

# Usage

See the [wiki](https://github.com/smoka7/hop.nvim/wiki).

# Keybindings

Hop doesn’t set any keybindings; you will have to define them by yourself.

If you want to create a key binding from within Lua:

```lua
-- place this in one of your configuration file(s)
local hop = require('hop')
local directions = require('hop.hint').HintDirection
vim.keymap.set('', 'f', function()
  hop.hint_char1({ direction = directions.AFTER_CURSOR, current_line_only = true })
end, {remap=true})
vim.keymap.set('', 'F', function()
  hop.hint_char1({ direction = directions.BEFORE_CURSOR, current_line_only = true })
end, {remap=true})
vim.keymap.set('', 't', function()
  hop.hint_char1({ direction = directions.AFTER_CURSOR, current_line_only = true, hint_offset = -1 })
end, {remap=true})
vim.keymap.set('', 'T', function()
  hop.hint_char1({ direction = directions.BEFORE_CURSOR, current_line_only = true, hint_offset = 1 })
end, {remap=true})
```


# Other tools like hop.nvim

* [sneak.nvim](https://github.com/justinmk/vim-sneak)
* [EasyMotion](https://github.com/easymotion/vim-easymotion)
* [Seek](https://github.com/goldfeld/vim-seek)
* [smalls](https://github.com/t9md/vim-smalls)
* [improvedft](https://github.com/chrisbra/improvedft)
* [clever-f](https://github.com/rhysd/clever-f.vim)
* [vim-extended-ft](https://github.com/svermeulen/vim-extended-ft)
* [Fanf,ingTastic;](https://github.com/dahu/vim-fanfingtastic)
* [IdeaVim-Sneak](https://plugins.jetbrains.com/plugin/15348-ideavim-sneak)
* [leap.nvim](https://github.com/ggandor/leap.nvim)
* [flash.nvim](https://github.com/folke/flash.nvim)

