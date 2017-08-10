local migrations = require('lapis.db.migrations')
local schema = require('lapis.db.schema')
local types = schema.types

local schemas = {
  [1] = function()
    schema.create_table('users', {
      { 'username', types.varchar },
      { 'password', types.text },
      { 'created_at', types.time },
      { 'updated_at', types.time },
      { 'change_required', types.boolean},
      { 'admin', types.boolean},
      "PRIMARY KEY(username)"
    })
  end,
}

migrations.run_migrations(schemas)
