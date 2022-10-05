#
# Cookbook:: jenkins
# Library:: ssh_executor
#

require_relative '_executor'

module Jenkins
  class SshExecutor < Executor

    #
    # Create a new Jenkins executor.
    #
    # @param [Hash] options
    #
    # @option options [Hash] :ssh_options
    # the ssh options (e.g log_level => QUIET)
    #
    # @return [Jenkins::Executor]
    #
    def initialize(options = {})
      @options = {
        ssh:         '/usr/bin/ssh',
        ssh_port:    33_591,
        ssh_options: {},
        timeout:     60,
      }.merge(options)
    end

    #
    # Run the given command string against the executor, raising any
    # exceptions to the main thread.
    #
    # @param [Array] pieces
    #   an array of commands to execute
    #
    # @return [String]
    #   the standard out from the command
    #
    def execute!(*pieces)
      raise 'Jenkins host unspecified' unless options[:host]

      command_options = pieces.last.is_a?(Hash) ? pieces.pop : {}
      command = []
      command << %("#{options[:ssh]}")
      if options[:ssh_options].is_a? Hash
        options[:ssh_options].each do |key, val|
          command << "-o#{key.split('_').map(&:capitalize).join}=#{val}"
        end
      end
      command << %(-u "#{options[:cli_user]}")           if options[:cli_user]
      command << %(-i "#{options[:key]}")                if options[:key]
      command << %(-p #{options[:ssh_port]})             if options[:ssh_port]
      command << options[:host]                          if options[:host]
      command.push(*pieces)

      execute_command!(command, command_options)
    end
  end
end
