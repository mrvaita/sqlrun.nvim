-- Run the command and add the requested parameters.
-- This code is adapted from https://www.youtube.com/watch?v=HlfjpstqXwE
-- Add your database connection information to `/.config/sql_run/sql_hosts.json`.
-- Connection information data must have the following format:
-- {
--         "connection_name": {
--                 "server": "servername",
--                 "port": 5432,
--                 "binary": "/usr/bin/psql"
--                 "user": "username",
--                 "password": "",
--                 "database": "",
--                 "is_remote": false,
--                 "db_type": "postgresql"
--         },
--         ...
-- }
local util = require("util")

local SqlRun = {
  client = "",
  database = "",
  connection = nil,
  result_buffers = {},
  config = { hosts_path = "~/.config/sqlrun.nvim/sql_hosts.json", ssh_tunnel = false },
}

function SqlRun.is_connection_available()
  return SqlRun.connection ~= nil
end

function SqlRun.get_current_connection_info()
  return string.format("%s:%s", SqlRun.client, SqlRun.database)
end

local function run_query(query)
  -- Delete old buffer if any
  local old_buf = table.remove(SqlRun.result_buffers)
  if old_buf ~= nil then
    vim.cmd('bd! ' .. old_buf)
  end

  -- write query to a file
  local tmp_query_file = os.tmpname()
  local f = io.open(tmp_query_file, 'w+')
  io.output(f)
  io.write(query)
  io.close(f)

  -- Create new buffer for the current query result
  vim.cmd('new')
  vim.opt.colorcolumn = ""
  local output_bufnr = vim.api.nvim_get_current_buf()
  -- Add query buffer to table (It can be deleted later)
  table.insert(SqlRun.result_buffers, output_bufnr)

  local append_data = function(_, data)
    if data then
      vim.api.nvim_buf_set_lines(output_bufnr, 0, 0, false, data)
    end
  end

  -- Finally format the real command that executes the query
  vim.fn.jobstart(string.format(SqlRun.connection["command"], tmp_query_file), {
    stdout_buffered = true,  -- Send me the output one line after the other
    on_stdout = append_data,
    on_stderr = append_data,
    on_exit = function() os.remove(tmp_query_file) end,
  })
end

function SqlRun.execute_buffer()
  if not SqlRun.is_connection_available() then
    return
  end
  local db_type = SqlRun.connection["db_type"]

  -- Get whole buffer content and write it to a file
  local bufcontent = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local query = ""
  for _, v in pairs(bufcontent) do
    query = query .. "\n" .. v
  end

  query = util.format_query(query, db_type)
  run_query(query)
end

-- NOTE: V-Block selection will not work because it is useless
function SqlRun.execute_selection()
  if not SqlRun.is_connection_available() then
    return
  end
  local db_type = SqlRun.connection["db_type"]

  local query = ""
  local get_query_string = function(lines)
    for _, line in ipairs(lines) do
      query = string.format("%s%s\n", query, line)
    end
    return query
  end

  -- Get selection boundaries (lines and columns)
  local selection_start = vim.api.nvim_buf_get_mark(0, "<")
  local selection_end = vim.api.nvim_buf_get_mark(0, ">")
  local start_line = selection_start[1]
  local start_col = selection_start[2]
  local end_line = selection_end[1]
  local end_col = selection_end[2] + 1

  -- get buffer portion from selection
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)

  if end_col == 2147483648 then  -- full line selection (ShiftV)
    query = get_query_string(lines)
  else  -- normal Visual mode selection
    local number_of_lines = #lines
    -- 1. trim first line until selection starts
    local query_first_line = string.sub(table.remove(lines, 1), start_col + 1)
    -- 2. trim last line after selection ends
    local query_last_line = ""
    if number_of_lines == 1 then -- If selection is only one line, the first and last line are the same
      query_first_line = string.sub(query_first_line, 0, end_col)
    else
      query_last_line = string.sub(table.remove(lines, #lines), 0, end_col)
    end
    -- 3. get the remaining lines
    if number_of_lines > 2 then  -- If selection is only two lines there is no body to process
      query = get_query_string(lines)
    end
    -- 4. put all the pieces together
    query = string.format("%s\n%s%s", query_first_line, query, query_last_line)
  end

  query = util.format_query(query, db_type)
  run_query(query)
end

function SqlRun.execute_current_line()
  if not SqlRun.is_connection_available() then
    return
  end
  local db_type = SqlRun.connection["db_type"]

  local line_number = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(0, line_number - 1, line_number, false)

  local query = util.format_query(lines[1], db_type)
  run_query(query)
end

function SqlRun.setup(config)
  SqlRun.config = vim.tbl_extend('force', SqlRun.config, config or {})
  if SqlRun.config.ssh_tunnel and vim.fn.executable("go") == 1 then
    vim.fn.jobstart("go build -o sshTunnel", { cwd = util.root_path() .. "/ssh_tunnel" })
  end
  vim.api.nvim_create_user_command("SqlRun", function()
    SqlRun.connection = nil
    -- Load databases connection params
    local databases = vim.fn.json_decode(util.lines_from(vim.fn.expand(SqlRun.config.hosts_path))) or {}
    local connections = {}
    for k, _ in pairs(databases) do
        table.insert(connections, k)
    end
    table.sort(connections)

    vim.ui.select(connections, { prompt = "Select a database connection"} , function(client)
      if client == nil then
        return
      end

      local server = databases[client].server
      local port = databases[client].port
      local binary = databases[client].binary
      local user = databases[client].user
      local password = databases[client].password
      local database = databases[client].database
      local ssh = databases[client].ssh
      local db_type = databases[client].db_type
      local ssh_tunnel = databases[client].ssh_tunnel

      SqlRun.connection = util.get_connection_string(
        server, port, user, password, database, binary, ssh, db_type, ssh_tunnel)
      if SqlRun.connection["command"] ~= "" then
        SqlRun.client = client
        SqlRun.database = SqlRun.connection["database"]
      end

      -- Call the function that executes query
      local map_opts = { noremap = true, silent = true, nowait = true }
      vim.api.nvim_buf_set_keymap(0, "n", "<leader>q", ":lua require('sqlrun').execute_buffer()<CR>", map_opts)
      vim.api.nvim_buf_set_keymap(0, "v", "<leader>q", ":lua require('sqlrun').execute_selection()<CR>", map_opts)
      vim.api.nvim_buf_set_keymap(0, "n", "<leader>l", ":lua require('sqlrun').execute_current_line()<CR>", map_opts)
    end)
  end, {})
end

return SqlRun
