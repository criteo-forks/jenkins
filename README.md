# jenkins Cookbook

This a fork of the [Jenkins Cookbook](https://github.com/sous-chefs/jenkins) adapted for *Criteo* use cases.

## Using Jenkins CLI over SSH

### Why use SSH instead of Jenkins CLI

The main issue with the `jenkins-cli.jar` is that it depends on the `Jenkins location` set in Jenkins (returned by the `x-ssh-endpoint`).\
This is not always desired as the Jenkins location purpose is to define the `JENKINS_URL` for http links.

Another drawback is the lack of options related to ssh itself. Currently, It doesn't allow disabling the host key verification for example.

### Enable Jenkins CLI over SSH

Set the attribute `node['jenkins']['executor']['use_ssh_client']` to `true` to use the ssh tool instead of `jenkins-cli.jar`. Also the `jenkins-cli.jar` won't be downloaded from the server when this is set.\
*NOTE.* The ssh command must be already installed by yourself.

### SSH attributes

- SSH path: `node['jenkins']['executor']['ssh'] = '/usr/bin/ssh'`
- Username: `node['jenkins']['executor']['cli_user'] = 'root'`
- Private Key: `node['jenkins']['executor']['private_key'] = '/root/.ssh/id_rsa`
- Port: `node['jenkins']['executor']['ssh_port'] = 33_591`
- SSH options: `node['jenkins']['executor']['ssh_options'] = { 'user_known_hosts_file' => '/dev/null', 'strict_host_key_checking' => 'no' }`
- Server host: `node['jenkins']['master']['host'] = jenkins-server.com`

With the configuration above, the `jenkins_command help` resource would execute:

```bash
/usr/bin/ssh -oUserKnownHostsFile=no -oUserKnownHostsFile=/dev/null -u root -i /root/.ssh/id_rsa -p 33591 jenkins-server.com help
```
