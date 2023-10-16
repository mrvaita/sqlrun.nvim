# sqlrun.nvim
Simple utility to execute SQL queries from within Neovim. The result of the query will be displayed in a horozontal split
in neovim.
### Supported databases
* Postgresql
* Mysql
### Default keybindings
* `<leader>q` (Normal mode) Execute whole file content
* `<leader>q` (Visual mode) Execute selected content
* `<leader>l` (Normal mode). Execute current line
## Usage
If the installation is successful and the host is correctly specified in the `sql_hosts.json` file, type `:SqlRun` from
    the buffer where the query is written. Follow the instructions to select the server and the database
    (if not specified in the host configuration) against which the query needs to be executed.
    At the end, the keybindings to execute the query will be available for the buffer.
# Installation
### Lazy
```lua
{
  'mrvaita/sqlrun.nvim',
  opts = {},
},
```
# Configuration
The only configuration parameter available is the path to a json file where the database connection parameters are
specified.
```lua
{
  'mrvaita/sqlrun.nvim',
  opts = { hosts_path = "~/.config/sqlrun.nvim/sql_hosts.json" },
}
```
The default file name is `~/.config/sqlrun.nvim/sql_hosts.json`. Each hosts specified in the configuration file
should have the following fields:
```json
{
        "connection_name": {
                "server": "servername",
                "binary": "/usr/bin/psql"
                "user": "username",
                "password": "",
                "database": "",
                "is_remote": false,
                "db_type": "postgresql"
        },
        ...
}
```
## Database on remote server
Remote servers can also be specified but for the plugin to work few conditions must be met. Remote queries are
executed via ssh connection and that means:
1. That the user can ssh into the server
2. That the user did ssh into the server at least once and added the server to the ssh known hosts (typing `yes` in the terminal)
3. That the user added the RSA or DSA identities to the authentication agent (eg `$ ssh-add ~/.ssh/id_rsa` and entered the password).
That way the password will not be requested the next time an ssh connection is performed.
