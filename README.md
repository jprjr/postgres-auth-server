# postgres-auth-server

This is an authentication server, similar to
[htpasswd-auth-server](https://github.com/jprjr/htpasswd-auth-server)
or [ldap-auth-server](https://github.com/jprjr/ldap-auth-server). All users
are stored in a Postgresql table, and there's a web interface. Administrators
can set user's passwords, and require a user to change their password on their
next login. Users can change their own passwords.

## Installation

### Install OpenResty

I have a repo for automatically installing OpenResty + luarocks -
https://github.com/jprjr/setup-openresty

```bash
git clone https://github.com/jprjr/setup-openresty /tmp/setup-openresty
/tmp/setup-openresty/setup-openresty --prefix=/opt/openresty
```

This will install openresty at `/opt/openresty`. You can then add
`/opt/openresty/bin` to your `PATH`, or make make symlinks from
`/usr/local/bin` to the binaries/scripts at `/opt/openresty/bin`, whichever
you prefer.

In all my examples, I'll assume you've somehow added `luarocks` to your PATH.

### Install other prerequisites, setup Postgres

You'll need `libyaml-dev` and `postgresql` installed

```bash
sudo apt-get install libyaml-dev postgresql
```

Then create a username, password, and database for postgres-auth-server.
You should change the below example to have a better password.

```bash
sudo -u postgres psql -c "create user psql_auth with password 'psql_auth'"
sudo -u postgres psql -c "create database psql_auth with owner psql_auth"
```

### Option 1: Install Globally with LuaRocks


```bash
sudo luarocks install postgres-auth-server
```

Assuming you used the `setup-openresty` script, then you'll
find `postgres-auth-server` at `/opt/openresty/bin/postgres-auth-server`

Create a file at `/etc/postgres-auth-server/config.yaml` -- there's an example
config.yaml file in this repo. Edit as needed.

Move on down to the Usage section

### Option 2: Self-contained install

You can setup `postgres-auth-server` to use its own `lua_modules` folder:

```
git clone https://github.com/jprjr/postgres-auth-server.git
postgres-auth-server
luarocks-openresty --tree=lua_modules make rockspecs/postgres-auth-server-dev-1.rockspec
```

Then launch with

```
./bin/postgres-auth-server
```

By default, `./bin/postgres-auth-server` will just try to use `lua` - you can
specify a lua binary to run with `-l (binary)`, ie:

`./bin/postgres-auth-server -l /opt/openresty/bin/lua`

## Usage

In any examples, substiute `postgres-auth-server` with
`./bin/posgres-auth-server` if you went for the self-contained
installation.

```bash
postgres-auth-server help

Usage: postgres-auth-server [-c /path/to/config.yaml] <action>
Available actions:
  add username -- interactively add user
  admin username -- make user admin
  unadmin username -- make user admin
  change username -- require change for user
  list -- list users
  import /path/to/htpasswd -- import existing htpasswd file
  run   -- run server
  check -- check config file
```

### `postgres-auth-server add (username)`

Prompts for a username, password, whether the user
should be an admin, and if the user should be forced
to change their password at next login.

### `postgres-auth-server admin (username)`

Makes (username) flagged as an admin user.

### `postgres-auth-server unadmin (username)`

Removes admin status from a user.

### `postgres-auth-server change (username)`

Forces a password change at next login.

### `postgres-auth-server list`

Lists usernames, admin status, password change required status

### `postgres-auth-server import /path/to/htpasswd`

Imports an existing htpasswd file.

If a user already exists, `postgres-auth-server` prints
a warning message indicating as such.

If the htpasswd file contains an encryption method
not supported by postgres-auth-server, the user is
*not* imported and a message is printed.

### `postgres-auth-server run`

Launches `postgres-auth-server`

### `postgres-auth-server check`

Attempts to parse the config file and checks for errors. Also tests
that the postgres credentials are valid.

