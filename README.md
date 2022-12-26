# norns.nvim

norns.vim is a [Neovim](https://neovim.io/) plugin for working remotely with
[monome norns](https://monome.org/docs/norns/).

Install using the plugin manager of your choice. The plugin has no dependencies.

See the plugin [help file](doc/norns.txt) for complete details on the plugin.

Example session: 

```vim
" Connect to the device and open an window on the device output. The default
" device is norns.local.
:Norns connect

" Execute code on the device. The output window displays the command and
" result of executing the command.
:Norns exec print('hello world')

" Load the awake script.
:Norns load code/awake/awake.lua

" Open a quickfix window on errors in the device output using a mapping from
" remote directories to local directories specified in the plugin
" configuration.
:Norns quickfix

" Reload the previous script, awake.
:Norns load

```
