local M = {}

function M.select_value(prompt_message, data)
    local result = nil
    vim.ui.select(data, { prompt = prompt_message }, function(selection)
      result = selection
    end)

    return result
end

function M.lines_from(file)
  local lines = ""
  for line in io.lines(file) do
    lines = lines .. " " .. line
  end
  return lines
end

function M.format_query(query_str, db_type)
  if string.lower(db_type) == "postgresql" then
    query_str = string.format("\\timing on \n%s", query_str)      -- show timing of queries
    query_str = string.format("\\pset border 2 \n%s", query_str)  -- show pretty lines outside the table
    query_str = string.format("\\set QUIET 1 \n%s", query_str)    -- no console output for the following commands
  elseif string.lower(db_type) == "mysql" then
    query_str = string.format("set profiling=1;\n%s", query_str)  -- Doesn't seem to work :\
  else
    error(string.format("Specified database type %s not implemented. Please use 'postgresql' or 'mysql'", db_type))
  end

  return query_str
end

local password_field = {
  mysql = "MYSQL_PWD",
  postgresql = "PGPASSWORD",
}

local user_option = {
  mysql = "-u",
  postgresql = "-U",
}

local database_option = {
  mysql = "",
  postgresql = "-d",
}

local port_option = {
  mysql = "-P",
  postgresql = "-p",
}

local get_dbs = {
  mysql = {
    query = "show databases;",
    cmd_opts = "-N",
  },
  postgresql = {
    query = "SELECT datname FROM pg_database WHERE datistemplate = false;",
    cmd_opts = "postgres -qAtX",
  },
}

local query_options = {
  mysql = "-t",
  postgresql = "",
}

function M.get_connection_string(server, port, user, password, db_name, binary, is_remote, db_type, ssh_tunnel)
  if db_type ~= "postgresql" and db_type ~= "mysql" then
    error(string.format("Specified database type %s not implemented. Please use 'postgresql' or 'mysql'", db_type))
  end

  local db_command_pattern = binary
  if password ~= "" then
    db_command_pattern = string.format("%s=%s %s", password_field[db_type], password, db_command_pattern)
  end
  if port ~= nil or port ~= "" then
    db_command_pattern = string.format("%s %s %s", db_command_pattern, port_option[db_type], port)
  end
  if user ~= "" then
    db_command_pattern = string.format("%s %s %s", db_command_pattern, user_option[db_type], user)
  end

  if db_name == "" then
    local dbs = nil
    if is_remote then
      dbs = string.format("echo \"%s\" | ssh %s \"%s %s %s\"", get_dbs[db_type].query, server, db_command_pattern, database_option[db_type], get_dbs[db_type].cmd_opts)
    else
      dbs = string.format("echo \"%s\" | %s %s %s", get_dbs[db_type].query, db_command_pattern, database_option[db_type], get_dbs[db_type].cmd_opts)
      if ssh_tunnel then
        dbs = string.format(
          "%s/.config/sqlrun.nvim/ssh_tunnel/sshTunnel -jump %s -remote %s -port %s -cmd '%s'",
          os.getenv("HOME"), ssh_tunnel.jump_host, ssh_tunnel.remote_host, port, dbs
        )
      end
    end

    -- Get list of databases for db_client
    local result = vim.fn.systemlist(dbs)
    local data = {}
    if result then
        for _, v in pairs(result) do
            table.insert(data, v)
        end
    end
    table.sort(data)

    db_name = M.select_value("\nSelect a database", data)
  end

  local connection_string = ""
  if is_remote then
    connection_string = "cat \"%s\" | " .. string.format("ssh %s %s %s %s %s", server, db_command_pattern, database_option[db_type], query_options[db_type], db_name)
  else
    connection_string = "cat \"%s\" | " .. string.format("%s %s %s %s", db_command_pattern, database_option[db_type], query_options[db_type], db_name)
    if ssh_tunnel then
      connection_string = string.format(
        "%s/.config/sqlrun.nvim/ssh_tunnel/sshTunnel -jump %s -remote %s -port %s -cmd '%s'",
        os.getenv("HOME"), ssh_tunnel.jump_host, ssh_tunnel.remote_host, port, connection_string
      )
    end
  end

  return { command = connection_string, database = db_name }
end

return M
