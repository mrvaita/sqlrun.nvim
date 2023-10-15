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
    query_str = string.format("%s", query_str)  -- postgresql option added directly in query string command
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

local get_dbs = {
  mysql = {
    query = "show databases;",
    cmd_opts = "",
  },
  postgresql = {
    query = "SELECT datname FROM pg_database WHERE datistemplate = false;",
    cmd_opts = "postgres -qAtX",
  },
}

local query_options = {
  mysql = "-t",
  postgresql = "-c '\\set QUIET 1' -c '\\timing' -c '\\pset border 2'",
}

local cmd_option = {
  mysql = "-e",
  postgresql = "-c",
}

function M.get_connection_string(server, user, password, db_name, binary, is_remote, db_type)
  if db_type ~= "postgresql" and db_type ~= "mysql" then
    error(string.format("Specified database type %s not implemented. Please use 'postgresql' or 'mysql'", db_type))
  end

  local db_command_pattern = binary
  if password ~= "" then
    db_command_pattern = string.format("%s=%s %s", password_field[db_type], password, db_command_pattern)
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
    connection_string = string.format("ssh %s \"%s %s %s %s %s", server, db_command_pattern, database_option[db_type], db_name, query_options[db_type], cmd_option[db_type]) .. " '%s'\""
  else
    connection_string = string.format("%s %s %s %s %s", db_command_pattern, database_option[db_type], db_name, query_options[db_type], cmd_option[db_type]) .. " '%s'"
  end

  return connection_string
end

return M
