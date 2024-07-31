#
# Cookbook:: jenkins
# Resource:: jnlp_slave
#
# Author:: Seth Chisamore <schisamo@chef.io>
#
# Copyright:: 2013-2019, Chef Software, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require_relative 'slave'

class Chef
  class Resource::JenkinsJnlpSlave < Resource::JenkinsSlave
    resource_name :jenkins_jnlp_slave # Still needed for Chef 15 and below
    provides :jenkins_jnlp_slave

    # Actions
    actions :create, :delete, :connect, :disconnect, :online, :offline
    default_action :create

    # Properties
    property :group, String,
              default: 'jenkins',
              regex: Config[:group_valid_regex]

    property :service_name, String,
              default: 'jenkins-slave'
    attribute :supplementary_groups,
              kind_of: Array,
              default: []

    property :service_groups, Array,
      default: lazy { [group] }

    # CRITEO Specific: [Linux] Support both runit and systemd
    property :use_systemd,
      kind_of: [TrueClass, FalseClass],
      default: true

    property :runit_scripts_cookbook, String,
      default: 'jenkins',
      description: 'Name of the cookbook holding the runsv script'

    deprecated_property_alias 'runit_groups', 'service_groups',
      '`runit_groups` was renamed to `service_groups` with the move to systemd services'
  end
end

class Chef
  class Provider::JenkinsJnlpSlave < Provider::JenkinsSlave
    provides :jenkins_jnlp_slave

    def load_current_resource
      @current_resource ||= Resource::JenkinsJnlpSlave.new(new_resource.name)

      super
    end

    action :create do
      do_create

      declare_resource(:directory, ::File.expand_path(new_resource.remote_fs, '..')) do
        recursive(true)
        action :create
      end

      unless platform?('windows')
        declare_resource(:group, new_resource.group) do
          system(node['jenkins']['master']['use_system_accounts'])
        end

        declare_resource(:user, new_resource.user) do
          gid(new_resource.group)
          comment('Jenkins slave user - Created by Chef')
          home(new_resource.remote_fs)
          system(node['jenkins']['master']['use_system_accounts'])
          action :create
        end
      end

      declare_resource(:directory, new_resource.remote_fs) do
        owner(new_resource.user)
        group(new_resource.group)
        recursive(true)
        action :create
      end

      service_name = new_resource.use_systemd ? "systemd_unit[#{new_resource.service_name}.service]" : "runit_service[#{new_resource.service_name}]"

      declare_resource(:remote_file, slave_jar).tap do |r|
        # We need to use .tap() to access methods in the provider's scope.
        r.source slave_jar_url
        r.backup(false)
        r.mode('0755')
        r.atomic_update(false)
        r.notifies :restart, service_name unless platform?('windows')
      end

      # The Windows's specific child class manages it's own service
      return if platform?('windows')

      if new_resource.use_systemd
        create_with_systemd
      else
        create_with_runit
      end
    end

    action :delete do
      # Stop and remove the service
      service "#{new_resource.service_name}" do
        action [:disable, :stop]
      end

      do_delete
    end

    private

    #
    # @see Chef::Resource::JenkinsSlave#launcher_groovy
    # @see http://javadoc.jenkins-ci.org/hudson/slaves/JNLPLauncher.html
    #
    def launcher_groovy
      'launcher = new hudson.slaves.JNLPLauncher()'
    end

    #
    # The path (url) of the slave's unique JNLP file on the Jenkins
    # master.
    #
    # @return [String]
    #
    def jnlp_url
      @jnlp_url ||= uri_join(endpoint, 'computer', new_resource.slave_name, 'slave-agent.jnlp')
    end

    def instance_identity
      return @instance_identity if @instance_identity
      @instance_identity = executor.groovy 'println(hudson.remoting.Base64.encode(org.jenkinsci.main.modules.instance_identity.InstanceIdentity.get().getPublic().getEncoded()))'
    end

    def jnlp_direct_host
      return @jnlp_direct_host if @jnlp_direct_host
      @jnlp_direct_host = executor.groovy 'println(System.getProperty("container.host.ip", InetAddress.localHost.hostAddress))'
    end

    def jnlp_direct_port
      return @jnlp_direct_port if @jnlp_direct_port
      @jnlp_direct_port = executor.groovy 'println(jenkins.model.Jenkins.instance.getSlaveAgentPort().toString())'
    end

    #
    # Generates the slaves unique JNLP secret using the Groovy API.
    #
    # @return [String]
    #
    def jnlp_secret
      return @jnlp_secret if @jnlp_secret
      json = executor.groovy! <<~EOH
        output = [
          secret:jenkins.slaves.JnlpSlaveAgentProtocol.SLAVE_SECRET.mac('#{new_resource.slave_name}')
        ]

        builder = new groovy.json.JsonBuilder(output)
        println(builder)
      EOH
      output = JSON.parse(json, symbolize_names: true)
      @jnlp_secret = output[:secret]
    end

    #
    # The url of the +slave.jar+ on the Jenkins master.
    #
    # @return [String]
    #
    def slave_jar_url
      @slave_jar_url ||= uri_join(endpoint, 'jnlpJars', 'slave.jar')
    end

    #
    # The checksum of the +slave.jar+.
    #
    # @return [String]
    #
    def slave_jar_checksum
      @slave_jar_checksum ||= new_resource.checksum
    end

    #
    # The path to the +slave.jar+ on disk (which may or may not exist).
    #
    # @return [String]
    #
    def slave_jar
      ::File.join(new_resource.remote_fs, 'slave.jar')
    end

    # Embedded Resources

    #
    # Creates a `group` resource that represents the system group
    # specified the `group` attribute. The caller will need to call
    # `run_action` on the resource.
    #
    # @return [Chef::Resource::Group]
    #
    def group_resource
      @group_resource ||= build_resource(:group, new_resource.group) do
        system(node['jenkins']['master']['use_system_accounts'])
      end
    end

    #
    # Creates a `user` resource that represents the system user
    # specified the `user` attribute. The caller will need to call
    # `run_action` on the resource.
    #
    # @return [Chef::Resource::User]
    #
    def user_resource
      @user_resource ||= build_resource(:user, new_resource.user) do
        gid(new_resource.group)
        comment('Jenkins slave user - Created by Chef')
        home(new_resource.remote_fs)
        system(node['jenkins']['master']['use_system_accounts'])
      end
    end

    #
    # Creates the parent `directory` resource that is a level above where
    # the actual +remote_fs+ will live. This is required due to a Chef/RedHat
    # bug where +--create-home-dir+ behavior changed and broke the Internet.
    #
    # @return [Chef::Resource::Directory]
    #
    def parent_remote_fs_dir_resource
      @parent_remote_fs_dir_resource ||=
        begin
          path = ::File.expand_path(new_resource.remote_fs, '..')
          build_resource(:directory, path) do
            recursive(true)
          end
        end
    end

    #
    # Creates a `directory` resource that represents the directory
    # specified the `remote_fs` attribute. The caller will need to call
    # `run_action` on the resource.
    #
    # @return [Chef::Resource::Directory]
    #
    def remote_fs_dir_resource
      @remote_fs_dir_resource ||= build_resource(:directory, new_resource.remote_fs) do
        owner(new_resource.user)
        group(new_resource.group)
        recursive(true)
      end
    end

    #
    # Creates a `remote_file` resource that represents the remote
    # +slave.jar+ file on the Jenkins master. The caller will need to
    # call `run_action` on the resource.
    #
    # @return [Chef::Resource::RemoteFile]
    #
    def slave_jar_resource
      @slave_jar_resource ||=
        begin
          build_resource(:remote_file, slave_jar).tap do |r|
            # We need to use .tap() to access methods in the provider's scope.
            r.source slave_jar_url
            r.checksum slave_jar_checksum
            r.backup(false)
            r.mode('0755')
            r.atomic_update(false)
          end
        end
    end

    #
    # Returns a fully configured service resource that can start the
    # JNLP slave process. The caller will need to call `run_action` on
    # the resource.
    #
    # @return [Chef::Resource::RunitService]
    #
    def create_with_runit
      # Ensure runit is installed on the slave.
      include_recipe 'runit'
      declare_resource(:runit_service, new_resource.service_name).tap do |r|
        # We need to use .tap() to access methods in the provider's scope.
        r.cookbook(new_resource.runit_scripts_cookbook)
        r.run_template_name('jenkins-slave')
        r.log_template_name('jenkins-slave')
        r.options(
          service_name:      new_resource.service_name,
          jvm_options:       new_resource.jvm_options,
          user:              new_resource.user,
          runit_groups:      new_resource.runit_groups,
          remote_fs:         new_resource.remote_fs,
          java_bin:          java,
          slave_jar:         slave_jar,
          jnlp_url:          jnlp_url,
          jnlp_secret:       jnlp_secret,
          direct_host:       jnlp_direct_host,
          direct_port:       jnlp_direct_port,
          instance_identity: instance_identity,
          slave_name:        new_resource.slave_name
        )
      end
    end

    def create_with_systemd
      # disable runit services before starting new service
      # TODO: remove in future version

      %W(
        /etc/init.d/#{new_resource.service_name}
        /etc/service/#{new_resource.service_name}
      ).each do |f|
        file f do
          action :delete
          notifies :stop, "service[#{new_resource.service_name}]", :before
        end
      end

      # runit_service = if platform_family?('debian')
      #                   'runit'
      #                 else
      #                   'runsvdir-start'
      #                 end
      # service runit_service do
      #   action [:stop, :disable]
      # end

      exec_string = "#{java} #{new_resource.jvm_options}"
      exec_string << " -cp #{slave_jar} hudson.remoting.jnlp.Main"
      exec_string << ' -headless'
      exec_string << " -workDir #{new_resource.remote_fs}"
      exec_string << " -direct #{jnlp_direct_host}:#{jnlp_direct_port}"
      exec_string << ' -protocols JNLP4-connect'
      exec_string << " -instanceIdentity #{instance_identity} #{jnlp_secret} #{new_resource.slave_name}"

      systemd_unit "#{new_resource.service_name}.service" do
        content <<~EOU
          #
          # Generated by Chef for #{node['fqdn']}
          # Changes will be overwritten!
          #

          [Unit]
          Description=Jenkins JNLP Slave (#{new_resource.service_name})
          After=network.target

          [Service]
          Type=simple
          User=#{new_resource.user}
          Group=#{new_resource.group}
          SupplementaryGroups=#{(new_resource.service_groups - [new_resource.group]).join(' ')}
          Environment="HOME=#{new_resource.remote_fs}"
          Environment="JENKINS_HOME=#{new_resource.remote_fs}"
          WorkingDirectory=#{new_resource.remote_fs}
          ExecStart=/bin/bash -lc "#{exec_string}"

          [Install]
          WantedBy=multi-user.target
        EOU
        action :create
      end

      service new_resource.service_name do
        action [:enable, :start]
      end
    end
  end
end
