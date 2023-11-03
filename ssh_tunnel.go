package main

import (
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"golang.org/x/crypto/ssh"
	"golang.org/x/crypto/ssh/agent"
	"golang.org/x/crypto/ssh/knownhosts"
)

type Endpoint struct {
	Host string
	Port int
	User string
}

func NewEndpoint(s string) *Endpoint {
	endpoint := &Endpoint{
		Host: s,
	}
	if parts := strings.Split(endpoint.Host, "@"); len(parts) > 1 {
		endpoint.User = parts[0]
		endpoint.Host = parts[1]
	}
	if parts := strings.Split(endpoint.Host, ":"); len(parts) > 1 {
		endpoint.Host = parts[0]
		endpoint.Port, _ = strconv.Atoi(parts[1])
	}
	return endpoint
}

func (endpoint *Endpoint) String() string {
	return fmt.Sprintf("%s:%d", endpoint.Host, endpoint.Port)
}

type SSHTunnel struct {
	Local  *Endpoint
	Server *Endpoint
	Remote *Endpoint
	Log    *log.Logger
}

func (tunnel *SSHTunnel) logf(fmt string, args ...interface{}) {
	if tunnel.Log != nil {
		tunnel.Log.Printf(fmt, args...)
	}
}

func (tunnel *SSHTunnel) createSshConfig() *ssh.ClientConfig {
	currentUser, err := user.Current()
	if err != nil {
		log.Fatal(err)
	}

	knownHostsCallback, err := knownhosts.New(filepath.Join(os.Getenv("HOME"), ".ssh", "known_hosts"))
	if err != nil {
		log.Fatal(err)
	}

	socket := os.Getenv("SSH_AUTH_SOCK")
	conn, err := net.Dial("unix", socket)
	if err != nil {
		log.Fatalf("Failed to open SSH_AUTH_SOCK: %v", err)
	}

	agentClient := agent.NewClient(conn)

	return &ssh.ClientConfig{
		User: currentUser.Username,
		Auth: []ssh.AuthMethod{
			ssh.PublicKeysCallback(agentClient.Signers),
		},
		HostKeyCallback:   knownHostsCallback,
	}
}

func (tunnel *SSHTunnel) Start() error {
	listener, err := net.Listen("tcp", tunnel.Local.String())
	if err != nil {
		return err
	}
	defer listener.Close()
	tunnel.Local.Port = listener.Addr().(*net.TCPAddr).Port
	for {
		conn, err := listener.Accept()
		if err != nil {
			return err
		}
		tunnel.logf("accepted connection")
		go tunnel.forward(conn)
	}
}

func (tunnel *SSHTunnel) forward(localConn net.Conn) {
	serverConn, err := ssh.Dial("tcp", tunnel.Server.String(), tunnel.createSshConfig())
	if err != nil {
		tunnel.logf("server dial error: %s", err)
		return
	}
	tunnel.logf("connected to %s (1 of 2)\n", tunnel.Server.String())
	remoteConn, err := serverConn.Dial("tcp", tunnel.Remote.String())
	if err != nil {
		tunnel.logf("remote dial error: %s", err)
		return
	}
	tunnel.logf("connected to %s (2 of 2)\n", tunnel.Remote.String())
	copyConn := func(writer, reader net.Conn) {
		_, err := io.Copy(writer, reader)
		if err != nil {
			tunnel.logf("io.Copy error: %s", err)
		}
	}
	go copyConn(localConn, remoteConn)
	go copyConn(remoteConn, localConn)
}

func (tunnel *SSHTunnel) RunShellCommand(shellCommand string) {
	var bashCommandString = []string{"bash", "-o", "pipefail"}
	output, err := exec.Command(
		bashCommandString[0],
		append(bashCommandString[1:], "-c", fmt.Sprintf("%s", shellCommand))...,
	).CombinedOutput()
	if err != nil {
		fmt.Printf("%s\n", err)
	}
	fmt.Printf("%s", output)
}

var (
	strJumpServer   string
	strRemoteServer string
	intLocalPort	int
	strCommand      string
)

func NewSSHTunnel(tunnel, destination string, localPort int) *SSHTunnel {
	// A random port will be chosen.
	localEndpoint := NewEndpoint(fmt.Sprintf("localhost:%d", localPort))
	server := NewEndpoint(tunnel)
	if server.Port == 0 {
		server.Port = 22
	}
	sshTunnel := &SSHTunnel{
		Local:  localEndpoint,
		Server: server,
		Remote: NewEndpoint(destination),
	}
	return sshTunnel
}

func main() {
	flag.StringVar(&strJumpServer, "jump", "user@jump.server:22", "Tunnel server. Default port 22 if not specified.")
	flag.StringVar(&strRemoteServer, "remote", "remote.server:3306", "Destination host and port of remote server.")
	flag.StringVar(&strCommand, "cmd", "echo \"show databases;\" | mysql dbname", "Command to execute against the remote server.")
	flag.IntVar(&intLocalPort, "port", 51015, "Local port")
	flag.Parse()
	// Setup the tunnel, but do not yet start it yet.
	tunnel := NewSSHTunnel(strJumpServer, strRemoteServer, intLocalPort)
	// Log connection info to file
	logFile, err := os.OpenFile(
		filepath.Join(os.Getenv("HOME"), ".config", "sqlrun.nvim", "ssh_tunnel", "ssh_tunnel.log"),
		os.O_APPEND|os.O_CREATE|os.O_WRONLY,
		0644,
	)
	if err != nil {
		log.Fatal(err)
	}
	defer logFile.Close()
	tunnel.Log = log.New(logFile, "", log.Ldate|log.Ltime)
	// Start the server in the background. You will need to wait a
	// small amount of time for it to bind to the localhost port before you can start sending connections.
	go tunnel.Start()
	time.Sleep(100 * time.Millisecond) // NewSSHTunnel will bind to a random port so that you can have
	// cmd := fmt.Sprintf("echo \"show databases;\" | MYSQL_PWD=REkPomRVPH8TWq5Q /usr/local/bin/mysql -u timmy-readonly -P %d -t timmy", tunnel.Local.Port)
	// cmd := fmt.Sprintf(strCommand, tunnel.Local.Port)
	// fmt.Println(cmd)
	tunnel.RunShellCommand(strCommand)
}
