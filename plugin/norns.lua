local api = vim.api

local prev_load = nil

local commands = {
  connect = {
    narg = 0,
    win = true,
    fn = function()
      require('norns').connect()
    end,
  },
  close = {
    narg = 0,
    fn = function()
      require('norns').close('Closed.')
    end,
  },
  exec = {
    win = true,
    fn = function(opts)
      table.remove(opts.fargs, 1)
      require('norns').exec(table.concat(opts.fargs, ' '))
    end,
  },
  quickfix = {
    narg = 0,
    fn = function()
      local qflist, err = require('norns').qflist()
      if not qflist then
        api.nvim_err_writeln(err)
        return
      end
      if #qflist == 0 then
        print('No errors found')
        return
      end
      vim.fn.setqflist(qflist)
      api.nvim_command('cc 1')
    end,
  },
  load = {
    narg = 1,
    win = true,
    fn = function(opts)
      local p = opts.fargs[2]
      if p then
        prev_load = p
      else
        p = prev_load
        if not p then
          api.nvim_err_writeln('Script argument required.')
          return
        end
      end
      require('norns').exec(string.format('norns.script.load(%q)', p))
    end,
  },
}

local names = vim.tbl_keys(commands)
table.sort(names)

vim.api.nvim_create_user_command('Norns', function(opts)
  local c = commands[opts.fargs[1]]
  if not c then
    api.nvim_err_writeln('Unknown subcommand ' .. opts.fargs[1])
    return
  end
  if c.narg and (#opts.fargs > c.narg + 1) then
    api.nvim_err_writeln('Unexpected argument.')
  end
  c.fn(opts)
  if c.win and not opts.bang then
    require('norns').ensure_window()
  end
end, {
  nargs = '+',
  complete = function(_, line)
    local a = vim.split(line, '%s+')
    local n = #a - 2
    if n == 0 then
      local c = vim.tbl_filter(function(name)
        return vim.startswith(name, a[2])
      end, names)
      if #c == 0 then
        c = names
      end
      return c
    end
  end,
})
