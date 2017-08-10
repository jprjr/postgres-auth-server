-- luacheck: globals ngx
local lapis = require'lapis'
local app = lapis.Application()
local respond_to = lapis.application.respond_to
local config = require'postgres-auth-server.config'.get()

local hmac_sha1 = ngx.hmac_sha1
local encode_base64 = ngx.encode_base64
local decode_base64 = ngx.decode_base64
local sort = table.sort
local lower = string.lower

local User = require'postgres-auth-server.models.user'

app.views_prefix = 'postgres-auth-server.views'
app:enable('etlua')
app.layout = require'postgres-auth-server.views.mainlayout'

app:before_filter(function(self)
  if self.session and self.session.user then
    if(encode_base64(hmac_sha1(config.secret,lower(self.session.user.username))) ==
       self.session.user.key) then
       self.user = User:find({ username = lower(self.session.user.username) })
    end
  end
  if self.session and self.session.status_msg then
    self.status_msg = self.session.status_msg
    self.session.status_msg = nil
  end
end)

app:match('splat', '*', respond_to({
  GET = function(self)
    return { redirect_to = self:url_for('site-root') }
  end,
}))

app:get('logout', config.http_prefix .. '/logout', function(self)
  self.session.user = nil
  return { redirect_to = self:url_for('login') }
end)

app:match('login', config.http_prefix .. '/login', respond_to({
  GET = function(_)
    return { render = 'login' }
  end,
  POST = function(self)
    local u = User:login(self.params.username, self.params.password)
    if u then
      self.session.user = {
        username = u.username,
        key = encode_base64(hmac_sha1(config.secret,u.username))
      }
      return { redirect_to = self:url_for('site-root') }
    else
      return { render = 'login' }
    end
  end,
}))

app:match('deleteuser', config.http_prefix .. '/user/:username/delete', respond_to({
  before = function(self)
    if not self.user then
      return { redirect_to = self:url_for('login') }
    end
    if not self.user.admin then
      return { redirect_to = self:url_for('site-root') }
    end
    self.edituser = User:find({ username = lower(self.params.username) })
    if not self.edituser then
      self.session.status_msg = { type = 'error', msg = 'User not found' }
      return { redirect_to = self:url_for('site-root') }
    end
  end,
  GET = function(_)
    return { render = 'deleteuser' }
  end,
  POST = function(self)
    self.edituser:delete()
    self.session.status_msg = { type = 'success', msg = 'User deleted' }
    return { redirect_to = self:url_for('site-root') }
  end,
}))

app:match('edituser', config.http_prefix .. '/user(/:username)', respond_to({
  before = function(self)
    if not self.user then
      return { redirect_to = self:url_for('login') }
    end
    if self.user.username ~= lower(self.params.username) and not self.user.admin then
      return { redirect_to = self:url_for('site-root') }
    end
    if self.params.username then
      self.edituser = User:find({ username = lower(self.params.username) })
      if not self.edituser then
        self.session.status_msg = { type = 'error', msg = 'User not found' }
        return { redirect_to = self:url_for('site-root') }
      end
    end
  end,
  GET = function(_)
    return { render = 'edituser' }
  end,
  POST = function(self)
    if self.edituser and self.user.username == self.edituser.username then
      if not self.user:check(self.params.password_cur) then
        self.session.status_msg = { type = 'error', msg = 'Current Password Incorrect' }
        return { redirect_to = self:url_for('edituser', { username = self.user.username }) }
      end
    end

    local updates = {}
    if not self.edituser then
      updates.username = lower(self.params.username)
    end
    if self.params.password ~= self.params.password_confirm then
      self.session.status_msg = { type = 'error', msg = "Passwords Don't Match" }
      return { redirect_to = self:url_for('edituser', { username = self.edituser.username }) }
    else
      updates.password = self.params.password
    end
    if self.params.change_required then
      updates.change_required = true
    else
      updates.change_required = false
    end
    if self.params.admin and self.user.admin then
      updates.admin = true
    else
      updates.admin = false
    end
    if not self.edituser then
      self.edituser = User:create(updates)
      self.session.status_msg = { type = 'success', msg = 'User Created' }
    else
      self.edituser:update(updates)
      self.session.status_msg = { type = 'success', msg = 'User Updated' }
    end
    return { redirect_to = self:url_for('site-root') }
  end,
}))

app:get('site-root', config.http_prefix .. '/', function(self)
  if not self.user then
    return { redirect_to = self:url_for('login') }
  end
  if self.user.change_required then
    return { redirect_to = self:url_for('changepassword') }
  end
  if self.user.admin then
    self.users = User:select()
    sort(self.users, function(a,b)
      return a.username < b.username
    end)
  end
  return { render = 'index' }
end)

app:get('auth', config.http_prefix .. '/auth', function(self)
  local function err_out(msg, code, headers)
    return {
      layout = 'plainlayout',
      content_type = 'text/plain',
      status = code,
      headers = headers,
    }, msg
  end

  local authorization = self.req.headers['authorization']

  if not authorization then
    return err_out('Authorization Required', 401, {
      ['WWW-Authenticate'] = 'Basic realm="' .. config.auth_realm .. '"'
    })
  end

  local userpassword = decode_base64(authorization:match("Basic%s+(.*)"));
  local username, password = userpassword:match("([^:]*):(.*)")

  local u = User:find({ username = lower(username) })

  if not u or u.change_required or not u:check(password) then
    return err_out('Authorization failed', 403)
  end

  return err_out(nil,204)

end)

return app
