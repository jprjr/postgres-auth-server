return [[
worker_processes <%= worker_processes %>;
error_log stderr <%= log_level %>;
daemon off;
pid logs/nginx.pid;

env CONFIG_FILE;

events {
  worker_connections 1024;
}

http {
  lua_socket_log_errors off;
  root <%= static_dir %>;

  resolver <%= dns_resolver %>;
  lua_ssl_trusted_certificate <%= ssl_trusted_certificate %>;
  lua_ssl_verify_depth <%= ssl_verify_depth %>;

  types {
    text/html                             html htm shtml;
    text/css                              css;
    text/plain                            txt;

    application/x-javascript              js;

    image/gif                             gif;
    image/jpeg                            jpeg jpg;
    image/png                             png;
    image/x-icon                          ico;
    image/svg+xml                         svg svgz;

  }

  init_by_lua_block {
    require'postgres-auth-server.config'.loadconfig(os.getenv('CONFIG_FILE'))
  }

  server {
    <% for _,v in ipairs(http_listen) do %>
    listen <%= v %>;
    <% end %>
    lua_code_cache on;

    location <%= http_prefix %>/ {
      default_type text/html;
      content_by_lua_block {
        require('lapis').serve('postgres-auth-server.webapp')
      }
    }

    location <%= http_prefix %>/static/ {
      alias <%= static_dir %>/static/;
    }

  }
}

]]
