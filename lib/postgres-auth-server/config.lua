local config = require'lapis.config'
local lyaml = require'lyaml'
local posix = require'posix'
local len = string.len
local sub = string.sub
local gsub = string.gsub

local config_loaded = false

local function find_static_dir()
  local static_dir
  static_dir = os.getenv('POSTGRES_AUTH_SERVER_STATIC_DIR')
  if static_dir then
    return static_dir
  end
  pcall(function()
    local search = require'luarocks.search'
    local path = require'luarocks.path'
    local name, ver, tree = search.pick_installed_rock('postgres-auth-server')
    if not name then
      return
    end
    static_dir = path.install_dir(name,ver,tree)
  end)
  if static_dir then
    return static_dir .. '/share/postgres-auth-server/html'
  end
end

local function find_conf_file(filename)
  filename = posix.stdlib.realpath(filename or '') or '/etc/postgres-auth-server/config.yaml'

  local search_filenames = { filename }
  local stat = require'posix.sys.stat'.stat

  pcall(function()
    local search = require'luarocks.search'
    local path = require'luarocks.path'
    local name, ver, tree = search.pick_installed_rock('postgres-auth-server')
    if not name then
      return
    end
    table.insert(search_filenames,
      path.conf_dir(name,ver,tree) .. '/config.yaml')
  end)


  for _,v in ipairs(search_filenames) do
    if stat(v) then
      return v
    end
  end

  return nil, search_filenames
end

local function loadconfig(filename)
  local f, yaml_string, yaml_config

  filename = find_conf_file(filename)

  if not filename then
    return nil, 'Unable to find config file'
  end

  f = io.open(filename,'r')

  if not f then
    return nil, 'Error loading config: unable to open ' .. filename
  end

  yaml_string = f:read('*all')
  f:close()

  local _, err = pcall(function()
    yaml_config = lyaml.load(yaml_string)
  end)

  if err then
    return nil, 'Error parsing ' .. filename .. ': ' .. err
  end

  if not yaml_config['encryption_method'] then
    yaml_config['encryption_method'] = 'sha512'
  end

  if not yaml_config['worker_processes'] then
    yaml_config['worker_processes'] = 1
  end

  if not yaml_config['log_level'] then
    yaml_config['log_level'] = 'error'
  end

  if not yaml_config['dns_resolver'] then
    yaml_config['dns_resolver'] = '8.8.8.8 ipv6=off'
  end

  if not yaml_config['ssl_trusted_certificate'] then
    yaml_config['ssl_trusted_certificate'] = '/etc/ssl/certs/ca-certificates.crt'
  end

  if not yaml_config['ssl_verify_depth'] then
    yaml_config['ssl_verify_depth'] = 5
  end

  if not yaml_config['http_listen'] then
    yaml_config['http_listen'] = { '[::]:8080 ipv6only=off' }
  end
  if type(yaml_config['http_listen']) == 'string' then
    yaml_config['http_listen'] = { yaml_config['http_listen'] }
  end

  if not yaml_config['work_dir'] then
    yaml_config['work_dir'] = os.getenv('HOME') .. '/.postgres-auth-server'
  end

  if not yaml_config.postgres.port then
    yaml_config.postgres.port = 5432
  end

  if not yaml_config.http_prefix then
    yaml_config.http_prefix = ''
  end

  if len(yaml_config.http_prefix) > 0 and sub(yaml_config.http_prefix,1,1) ~= '/' then
    yaml_config.http_prefix = '/' .. yaml_config.http_prefix
  end

  if not yaml_config.static_dir or len(yaml_config.static_dir) == 0 then
    local static_dir = find_static_dir()
    if not static_dir then
      return nil, 'Unable to find static files directory, set static_dir'
    end
    yaml_config.static_dir = static_dir
  end

  if not yaml_config.auth_realm then
    yaml_config.auth_realm = 'default'
  end

  gsub(yaml_config.http_prefix,'/+$','')

  config('default',yaml_config)

  package.loaded['lapis_environment'] = 'default'
  yaml_config['_filename'] = filename
  local sani_config = lyaml.load(lyaml.dump({yaml_config}))
  sani_config.postgres = nil
  yaml_config['_raw'] = lyaml.dump({sani_config})
  config_loaded = true

  return true

end

local function get()
  if not config_loaded then
    loadconfig()
  end
  return config.get()
end

return {
  find_conf_file = find_conf_file,
  loadconfig = loadconfig,
  get = get,
}
