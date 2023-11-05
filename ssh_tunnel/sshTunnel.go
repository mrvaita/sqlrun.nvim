// Adapted from https://github.com/elliotchance/sshtunnel
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

type endpoint struct {
	Host string
	Port int
	User string
}

func NewEndpoint(s string) *endpoint {
	endpoint := &endpoint{
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

func (endpoint *endpoint) String() string {
	return fmt.Sprintf("%s:%d", endpoint.Host, endpoint.Port)
}

type sshTunnel struct {
	Local  *endpoint
	Server *endpoint
	Remote *endpoint
	Log    *log.Logger
}

func NewSSHTunnel(tunnel, destination string, localPort int) *sshTunnel {
	// A random port will be chosen.
	localEndpoint := NewEndpoint(fmt.Sprintf("localhost:%d", localPort))
	server := NewEndpoint(tunnel)
	if server.Port == 0 {
		server.Port = 22
	}
	sshTunnel := &sshTunnel{
		Local:  localEndpoint,
		Server: server,
		Remote: NewEndpoint(destination),
	}
	return sshTunnel
}

func (tunnel *sshTunnel) createSshConfig() *ssh.ClientConfig {
	currentUser, err := user.Current()
	if err != nil {
		tunnel.Log.Fatalf("Cannot get current user: %s", err)
	}

	knownHostsCallback, err := knownhosts.New(filepath.Join(os.Getenv("HOME"), ".ssh", "known_hosts"))
	if err != nil {
		tunnel.Log.Fatalf("Cannot get known hosts: %s", err)
	}

	socket := os.Getenv("SSH_AUTH_SOCK")
	conn, err := net.Dial("unix", socket)
	if err != nil {
		tunnel.Log.Fatalf("Failed to open SSH_AUTH_SOCK: %v", err)
	}

	agentClient := agent.NewClient(conn)

	return &ssh.ClientConfig{
		User: currentUser.Username,
		Auth: []ssh.AuthMethod{
			ssh.PublicKeysCallback(agentClient.Signers),
		},
		HostKeyCallback: knownHostsCallback,
	}
}

func (tunnel *sshTunnel) Start() {
	listener, err := net.Listen("tcp", tunnel.Local.String())
	if err != nil {
		tunnel.Log.Fatalf("connection error: %s", err)
	}
	defer listener.Close()
	tunnel.Local.Port = listener.Addr().(*net.TCPAddr).Port
	for {
		conn, err := listener.Accept()
		if err != nil {
			tunnel.Log.Fatalf("connection error: %s", err)
		}
		tunnel.Log.Printf("accepted connection")
		go tunnel.forward(conn)
	}
}

func (tunnel *sshTunnel) forward(localConn net.Conn) {
	serverConn, err := ssh.Dial("tcp", tunnel.Server.String(), tunnel.createSshConfig())
	if err != nil {
		tunnel.Log.Fatalf("server dial error: %s", err)
	}
	tunnel.Log.Printf("connected to %s (1 of 2)\n", tunnel.Server.String())
	remoteConn, err := serverConn.Dial("tcp", tunnel.Remote.String())
	if err != nil {
		tunnel.Log.Fatalf("remote dial error: %s", err)
	}
	tunnel.Log.Printf("connected to %s (2 of 2)\n", tunnel.Remote.String())
	copyConn := func(writer, reader net.Conn) {
		_, err := io.Copy(writer, reader)
		if err != nil {
			tunnel.Log.Fatalf("io.Copy error: %s", err)
		}
	}
	go copyConn(localConn, remoteConn)
	go copyConn(remoteConn, localConn)
}

func (tunnel *sshTunnel) runShellCommand(shellCommand string) {
	var bashCommandString = []string{"bash", "-o", "pipefail"}
	output, err := exec.Command(
		bashCommandString[0],
		append(bashCommandString[1:], "-c", fmt.Sprintf("%s", shellCommand))...,
	).CombinedOutput()
	if err != nil {
		tunnel.Log.Printf("ERROR: %s", err)
		tunnel.Log.Printf("OUTPUT: %s", output)
		fmt.Printf("%s\n", err)
	}
	fmt.Printf("%s", output)
}

func main() {
	var (
		strJumpServer   string
		strRemoteServer string
		intLocalPort    int
		strCommand      string
	)
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
	tunnel.runShellCommand(strCommand)
}
