-- luacheck: globals ngx
local Model = require('lapis.db.model').Model
local config = require'postgres-auth-server.config'.get()
local crypt = require'crypt'
local lower = string.lower

local User = Model:extend('users', {
  primary_key = 'username',
  timestamp = true,
  update = function(self,t)
    if t.username then
      t.username = nil
    end
    if t.password then
      t.password = crypt.encrypt(config.encryption_method,t.password)
    end
    return Model.update(self,t)
  end,
  check = function(self,password)
    return crypt.check(password,self.password)
  end,
})

function User:login(username,password)
  local u = self:find({ username = lower(username) })
  if not u then
    return nil, 'user not found'
  end
  if not u:check(password) then
    return nil, 'invalid pasword'
  end
  return u
end

function User:create(t)
  if t.password then
    t.password = crypt.encrypt(config.encryption_method,t.password)
  end
  if t.username then
    t.username = lower(t.username)
  end

  return Model.create(self,t)
end

function User:import(username,password)
  username = lower(username)
  local u = User:find({ username = username })
  if not u then
    return Model.create(self,{
      username = username,
      password = password,
    })
  end
  return false, 'User exists'
end

return User;

