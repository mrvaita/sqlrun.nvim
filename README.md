# sqlrun.nvim
Simple utility to execute SQL queries from within Neovim. The result of the query will be displayed in a horizontal split
in Neovim.
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
### lazy.nvim
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
                "port": 5432,
                "binary": "/usr/bin/psql"
                "user": "username",
                "password": "",
                "database": "",
                "is_remote": false,
                "db_type": "postgresql"
        }
}
```
## Database on remote server
Remote servers can also be specified but for the plugin to work few conditions must be met. Remote queries are
executed via ssh connection and that means:
1. That the user can ssh into the server
2. That the user did ssh into the server at least once and added the server to the ssh known hosts (typing `yes` in the terminal)
3. That the user added the RSA or DSA identities to the authentication agent (eg `$ ssh-add ~/.ssh/id_rsa` and entered the password).
That way the password will not be requested the next time an ssh connection is performed.

### Use ssh port forwarding through jump host
If necessary, it is possible to open an ssh tunnel via jump host to reach the database server. This is equivalent to the
ssh command `ssh -L local_port:remote.server.net:database_port jump.host.net`. This is achieved with a go script included
in the plugin. I decided to include this functionality just to avoid to open a new terminal and execute the ssh command.
#### Drawbacks
* The go program is built everytime neovim is started. Doesn't take long though
#### HOW IT WORKS
* Go >= 1.21 must be installed and present in the path
* On neovim start the go program is built in the directory where the plugin is installed
* Ssh logs are saved to a file under `~/.config/sqlrun.nvim/ssh_tunnel`
* Only the current user is supported to connect to the jump host
* The jump host must be present in the list of `known_hosts`
* Authentication is performed exclusively with ssh agent
* Plugin options should at least look like `opts = { ssh_tunnel = true }`
* The database host in the json file should be specified like
```json
{
        "connection_name": {
                "server": "servername",
                "port": 51015,
                "binary": "/usr/bin/psql"
                "user": "username",
                "password": "",
                "database": "",
                "is_remote": false,
                "db_type": "postgresql"
                "ssh_tunnel": {
                    "jump_host": "jump.host.net:ssh_port",
                    "remote_host": "remote.host.net:remote_port"
                }
        }
}
```
* If the jump host `ssh_port` is not specified the port 22 will be used
* The `port` option in this case refers to the local port where the traffic from the remote host is forwarded.
The database port should be specified under `remote_host`
* `is_remote` option must be set to false

## Lualine integration
SqlRun can use [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim) to display connection information in the following way
```lua
local sqlrun = require('sqlrun')
require('lualine').setup{
  sections = {
    lualine_x = {
      { sqlrun.get_current_connection_info, cond = sqlrun.is_connection_available },
    },
  },
}
```
The connection info will be displayed as `<connection-name>:<database-name>`
