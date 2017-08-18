local posix  = require'posix'
local crypt  = require'crypt'
local pgmoon = require'pgmoon'
local getopt = require'postgres-auth-server.getopt'
local config = require'postgres-auth-server.config'
local lecho  = require'lecho'
local etlua  = require'etlua'

local unpack = unpack or table.unpack --luacheck: compat
local insert = table.insert
local lower  = string.lower
local sub    = string.sub
local find   = string.find
local len    = string.len

local version = '1.0.0'

local optarg, optind

local function help(code)
  io.stderr:write('Usage: postgres-auth-server [-c /path/to/config.yaml] <action>\n')
  io.stderr:write('Available actions:\n')
  io.stderr:write('  import /path/to/htpasswd -- import existing htpasswd file\n')
  io.stderr:write('  run   -- run server\n')
  io.stderr:write('  check -- check config file\n')
  io.stderr:write('  add username -- interactively add user\n')
  io.stderr:write('  admin username -- make user admin\n')
  io.stderr:write('  unadmin username -- make user admin\n')
  io.stderr:write('  change username -- require change for user\n')
  io.stderr:write('  list -- list users\n')
  return code
end

local function try_load_config(check)
  check = check or false
  local filename,filename_list,err,_
  filename, filename_list = config.find_conf_file(optarg['c'])
  if not filename then
    io.stderr:write('Unable to find config file. Searched paths:\n')
    for _,v in pairs(filename_list) do
      io.stderr:write('  ' .. v .. '\n')
    end
    return 1
  end

  if check then
    io.stderr:write('Testing config file ' .. filename .. '\n')
  end
  _,err = config.loadconfig(filename)
  if err then
    io.stderr:write('Error loading config: ' .. err .. '\n')
    return 1
  end

  local c = config.get()

  if not crypt.methods[c['encryption_method']] then
    io.stderr:write('Unsupported encryption_method\n')
    return 1
  end

  if not c['nginx_path'] then
    io.stderr:write('nginx_path not specified\n')
    return 1
  end

  if not posix.stdlib.realpath(c['nginx_path']) then
    io.stderr:write('path to nginx does not exist\n')
    return 1
  end

  local nginx_handle = io.popen(c['nginx_path'] .. ' -V 2>&1 | grep lua')
  local res = nginx_handle:read('*all')
  nginx_handle:close()

  if len(res) == 0 then
    io.stderr:write("nginx doesn't support lua\n")
    return 1
  end

  if not c['postgres'] or type(c['postgres']) ~= 'table' then
    io.stderr:write('config missing postgres section\n')
    return 1
  end

  local pg = pgmoon.new(c['postgres'])
  _, err = pg:connect()
  if err then
    io.stderr:write('Unable to connect to postgres: ' .. err .. '\n')
    return 1
  end

  if optarg['V'] then
    io.stderr:write(c['_raw'] .. '\n')
  end

  if check then
    io.stderr:write('OK\n')
  end

  return 0
end

local functions = {
  ['list'] = function()
    local res = try_load_config()
    if res ~= 0 then
      return res
    end
    require'postgres-auth-server.migrations'

    io.stdout:write(string.format('Username            |Change Required     |Admin\n'))
    io.stdout:write('--------------------|--------------------|--------------------\n')

    local User = require'postgres-auth-server.models.user'
    local users = User:select()
    for _,u in ipairs(users) do
      local c_string = u.change_required and 'true' or 'false'
      local a_string = u.admin and 'true' or 'false'
      while(len(u.username) < 20) do
        u.username = u.username .. ' '
      end
      if len(u.username) > 20 then
        u.username = sub(u.username,1,20)
      end
      while(len(c_string)) < 20 do
        c_string = c_string .. ' '
      end
      io.stdout:write(string.format('%s|%s|%s\n',u.username,c_string,a_string))
    end
    return 0
  end,

  ['admin'] = function(username)
    if not username then
      return help(1)
    end

    local res = try_load_config()
    if res ~= 0 then
      return res
    end

    require'postgres-auth-server.migrations'
    local User = require'postgres-auth-server.models.user'

    local u = User:find({ username = username })
    if not u then
      io.stdout:write('Unable to find user\n')
      return 1
    end
    u:update({admin = true})
    io.stdout:write(username .. ' is now an admin\n')
    return 0
  end,
  ['unadmin'] = function(username)
    if not username then
      return help(1)
    end

    local res = try_load_config()
    if res ~= 0 then
      return res
    end

    require'postgres-auth-server.migrations'
    local User = require'postgres-auth-server.models.user'

    local u = User:find({ username = username })
    if not u then
      io.stdout:write('Unable to find user\n')
      return 1
    end
    u:update({admin = true})
    io.stdout:write(username .. ' is no longer an admin\n')
    return 0
  end,
  ['change'] = function(username)
    if not username then
      return help(1)
    end

    local res = try_load_config()
    if res ~= 0 then
      return res
    end

    require'postgres-auth-server.migrations'
    local User = require'postgres-auth-server.models.user'

    local u = User:find({ username = username })
    if not u then
      io.stdout:write('Unable to find user\n')
      return 1
    end
    u:update({change_required = true})
    io.stdout:write(username .. ' needs to change their password at next login\n')
    return 0
  end,

  ['count'] = function()
    local res = try_load_config()
    if res ~= 0 then
      return res
    end

    local User = require'postgres-auth-server.models.user'
    local users = User:select()
    if not users then
      users = {}
    end
    print(#users)
    return 0
  end,

  ['add'] = function(username)

    local res = try_load_config()
    if res ~= 0 then
      return res
    end

    require'postgres-auth-server.migrations'
    local User = require'postgres-auth-server.models.user'

    if not username then
      io.stdout:write('Username: ')
      username = io.read()
    end

    local u = User:find({ username = username })
    if not u then
      io.stdout:write('Creating new user: ' .. username .. '\n')
    else
      io.stdout:write('Updating password for user: ' .. username .. '\n')
    end

    lecho:off()
    io.stdout:write('Password: ')
    local password = io.read()
    io.stdout:write('\nConfirm password: ')
    local cpassword = io.read()
    io.stdout:write('\n')
    lecho:on()
    if password ~= cpassword then
      io.stdout:write('Paswords do not match\n')
      return 1
    end

    local ut = {
      username = username,
      password = password,
      change_required = false,
    }

    io.stdout:write('Force password change at next login? [y/N] ')
    local force = io.read()
    if lower(sub(force,1,1)) == 'y' then
      ut.change_required = true
    end

    io.stdout:write('Make user an admin? [y/N] ')
    local admin = io.read()
    if lower(sub(admin,1,1)) == 'y' then
      ut.admin = true
    end

    io.stdout:write('Summary of changes:\n')
    if not u then
      io.stdout:write('Creating user ' .. username .. '\n')
    else
      io.stdout:write('Updating user ' .. username .. '\n')
    end
    local c_string = ut.change_required and 'true' or 'false'
    local a_string = ut.admin and 'true' or 'false'
    io.stdout:write('  Password change required: ' .. c_string .. '\n')
    io.stdout:write('  Administrator: ' .. a_string .. '\n')

    if not u then
      u = User:create(ut)
    else
      u:update(ut)
    end

    if not u then
      io.stdout:write('Failed to create/update user\n')
      return 1
    end

    return 0

  end,
  ['run'] = function()
    local res = try_load_config()
    if res ~= 0 then
      return res
    end
    local c = config.get()

    if not posix.stdlib.realpath(c['work_dir']) then
      posix.mkdir(c['work_dir'])
    end
    if not posix.stdlib.realpath(c['work_dir'] .. '/logs') then
      posix.mkdir(c['work_dir'] .. '/logs')
    end

    posix.setenv('CONFIG_FILE',c._filename)
    posix.setenv('LUA_PATH',package.path)
    posix.setenv('LUA_CPATH',package.cpath)

    local nginx_conf = etlua.compile(require'postgres-auth-server.nginx-conf')
    local nof = io.open(c['work_dir'] .. '/nginx.conf', 'wb')
    nof:write(nginx_conf(c))
    nof:close()

    require'postgres-auth-server.migrations'
    posix.exec(c['nginx_path'], { '-p', c['work_dir'], '-c', c['work_dir'] .. '/nginx.conf' } )
    return 0
  end,
  ['import'] = function(file)
    local res = try_load_config()
    if res ~= 0 then
      return res
    end
    if not file then
      return help()
    end
    local filename = posix.stdlib.realpath(file)
    if not filename then
      io.stderr:write('Unable to find ' .. file .. '\n')
      return 1
    end

    local f,ferr = io.open(filename,'r')
    if not f then
      io.stderr:write('Unable to open ' .. filename .. ': ' .. ferr .. '\n')
      return 1
    end
    io.stderr:write('Importing users from ' .. filename .. '\n')
    require'postgres-auth-server.migrations'

    local User = require'postgres-auth-server.models.user'
    local lineno = 1
    for line in f:lines() do
      local col_loc = find(line,':')
      if col_loc then
        local username = sub(line,1,col_loc-1)
        local password = sub(line,col_loc+1)
        local u,err = User:import(username,password)
        if not u then
          io.stderr:write('Line ' .. lineno .. ': Error importing ' .. username .. ' - ' .. err .. '\n')
        else
          io.stderr:write('Line ' .. lineno .. ': Successfully imported ' .. username .. '\n')
        end
      else
        io.stderr:write('Line ' .. lineno .. ': Malformed line\n')
      end
      lineno = lineno + 1
    end

    return 0
  end,
  ['check'] = function()
    return try_load_config(true)
  end,
}

local function main(args)
  local _, err
  _, err = pcall(function()
    optarg,optind = getopt.get_opts(args,'l:hVvc:',{})
  end)

  if err then
    io.stderr:write('Error parsing argments: ' .. err .. '\n')
    return help(1)
  end

  if optarg['v'] then
    io.stderr:write('postgres-auth-server: version ' .. version .. '\n')
    return 0
  end

  if optarg['h'] then
    return help(0)
  end

  if not args[optind] or not functions[args[optind]] then
    return help(1)
  end

  local func_args = {}
  for k=optind+1,#args,1 do
    insert(func_args,args[k])
  end

  return functions[args[optind]](unpack(func_args))
end

return main
