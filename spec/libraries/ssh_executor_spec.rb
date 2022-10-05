require 'spec_helper'

describe Jenkins::SshExecutor do
  describe '.initialize' do
    it 'uses default options' do
      options = described_class.new.options
      expect(options[:ssh]).to eq('/usr/bin/ssh')
      expect(options[:ssh_port]).to eq(33_591)
      expect(options[:ssh_options]).to eq({})
    end

    it 'overrides with options from the initializer' do
      options = described_class.new(ssh: '/bin/ssh', ssh_port: 12345, ssh_options: { 'log_level' => 'ERROR' }).options
      expect(options[:ssh]).to eq('/bin/ssh')
      expect(options[:ssh_port]).to eq(12345)
      expect(options[:ssh_options]).to eq({ 'log_level' => 'ERROR' })
    end
  end

  describe '#execute!' do
    context 'when parsing options' do
      before do
        allow(subject).to receive(:execute_command!)
        subject.options[:host] = 'localhost'
      end

      it 'host is not given' do
        subject.options[:host] = nil
        expect { subject.execute!('cmd') }.to raise_error(RuntimeError)
      end

      it 'host is given' do
        expect(subject).to receive(:execute_command!).with(array_including('localhost'), anything)
        subject.execute!('cmd')
      end

      it 'ssh options are given' do
        subject.options[:ssh_options] = { 'log_level' => 'ERROR', 'strict_host_key_checking' => 'no' }
        expect(subject).to receive(:execute_command!)
          .with(array_including('-oLogLevel=ERROR', '-oStrictHostKeyChecking=no'), anything)
        subject.execute!('cmd', {})
      end

      it 'ssh path is given' do
        subject.options[:ssh] = '/bin/ssh'
        expect(subject).to receive(:execute_command!).with(array_including('"/bin/ssh"'), anything)
        subject.execute!('cmd')
      end

      it 'ssh port is given' do
        subject.options[:ssh_port] = 22
        expect(subject).to receive(:execute_command!).with(array_including('-p 22'), anything)
        subject.execute!('cmd')
      end

      it 'user is given' do
        subject.options[:cli_user] = 'nobody'
        expect(subject).to receive(:execute_command!).with(array_including('-u "nobody"'), anything)
        subject.execute!('cmd')
      end

      it 'key is given' do
        subject.options[:key] = '/root/.ssh/id_rsa'
        expect(subject).to receive(:execute_command!).with(array_including('-i "/root/.ssh/id_rsa"'), anything)
        subject.execute!('cmd')
      end

      it 'command args given' do
        expect(subject).to receive(:execute_command!).with(anything, { 'arg1' => 'val1', 'arg2' => 'val2' })
        subject.execute!('cmd', { 'arg1' => 'val1', 'arg2' => 'val2' })
      end

      it 'all options given' do
        subject.options[:ssh]         = '/bin/ssh'
        subject.options[:ssh_options] = { 'user_known_hosts' => '/dev/null', 'log_level' => 'INFO' }
        subject.options[:cli_user]    = 'root'
        subject.options[:ssh_port]    = 12_345
        subject.options[:key]         = '/root/.ssh/id_rsa'
        expect(subject).to receive(:execute_command!)
          .with(['"/bin/ssh"', '-oUserKnownHosts=/dev/null', '-oLogLevel=INFO',
                 '-u "root"', '-i "/root/.ssh/id_rsa"', '-p 12345', 'localhost',
                 'online-node', 'fake-node'], {})
        subject.execute!('online-node', 'fake-node')
      end
    end

    context 'when a :key option is given' do
      context 'the private key is unknown to the Jenkins instance' do
        before do
          # This is really ugly but there is no easy way to stub a method to
          # raise an exception a set number of times.
          @times = 0
          allow(shellout).to receive(:error!) do
            @times += 1
            raise Mixlib::ShellOut::ShellCommandFailed unless @times > 2
          end
          allow(shellout).to receive(:exitstatus).and_return(255, 1, 0)
          allow(shellout).to receive(:stderr).and_return(
            'Authentication failed. No private key accepted.',
            'Exception in thread "main" java.io.EOFException',
            ''
          )
        end
      end
    end

    context 'when the command fails' do
      let(:shellout) { double(run_command: nil, error!: nil, stdout: '') }
      before { allow(Mixlib::ShellOut).to receive(:new).and_return(shellout) }
      it 'raises an error' do
        allow(shellout).to receive(:error!).and_raise(RuntimeError)
        expect { subject.execute!('bad') }.to raise_error(RuntimeError)
      end
    end
  end

  describe '#execute' do
    before { allow(subject).to receive(:execute!) }

    it 'calls #execute!' do
      expect(subject).to receive(:execute).with('foo', 'bar')
      subject.execute('foo', 'bar')
    end

    context 'when the command fails' do
      it 'does not raise an error' do
        allow(subject).to receive(:execute!).and_raise(Mixlib::ShellOut::ShellCommandFailed)
        expect { subject.execute('foo') }.to_not raise_error
      end
    end
  end
end
