require 'spec_helper'

class Subject
  include Jenkins::Helper

  attr_accessor :node

  def initialize
    @node = Node.new
  end

  class Node < Chef::Node::VividMash
    attr_accessor :run_state

    def initialize(_ = nil, __ = nil)
      @run_state = Chef::Node::VividMash.new
    end
  end
end

describe Subject do
  before do
    allow(subject).to receive(:wait_until_ready!)
    subject.node['java'] = nil
  end

  it 'when using jenkins-cli.jar' do
    allow(subject).to receive(:ensure_cli_present!)
    allow(Jenkins::Executor).to receive(:new)
    expect(subject).to receive(:ensure_cli_present!)
    expect(Jenkins::Executor).to receive(:new)
    expect(Jenkins::SshExecutor).not_to receive(:new)
    subject.executor
  end

  it 'when using ssh' do
    subject.node['jenkins']['executor'] = {
      'use_ssh_client' => true,
      'cli_user'       => 'root',
      'ssh_port'       => 33_592,
      'ssh_options'    => {
        'user_known_hosts_file'    => '/dev/null',
        'strict_host_key_checking' => 'no',
      },
    }
    subject.node['jenkins']['master']['host'] = 'jenkins-server.com'
    subject.node.run_state[:jenkins_private_key_path] = '/root/.ssh/id_rsa'

    allow(Jenkins::SshExecutor).to receive(:new)
    expect(subject).not_to receive(:ensure_cli_present!)
    expect(Jenkins::Executor).not_to receive(:new)
    expect(Jenkins::SshExecutor).to receive(:new)
      .with(hash_including(
        cli_user: 'root',
        key: '/root/.ssh/id_rsa',
        ssh_port: 33_592,
        ssh_options: {
        'user_known_hosts_file'    => '/dev/null',
        'strict_host_key_checking' => 'no',
        }
      ))
    subject.executor
  end
end
