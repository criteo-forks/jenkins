require 'json'

unified_mode true

resource_name :jenkins_jnlp_agent
provides :jenkins_jnlp_agent
provides :jenkins_jnlp_slave # Backwards compatibility alias

# Inherit properties from base agent resource
property :slave_name, String, name_property: true
property :description, String,
         default: lazy { |r| "Jenkins agent #{r.slave_name}" }
property :remote_fs, String, default: '/home/jenkins'
property :executors, Integer, default: 1
property :usage_mode, String, equal_to: %w(exclusive normal), default: 'normal'
property :labels, Array, default: []
property :availability, String, equal_to: %w(always demand)
property :in_demand_delay, Integer, default: 0
property :idle_delay, Integer, default: 1
property :environment, Hash
property :offline_reason, String
property :user, String, regex: [Chef::Config[:user_valid_regex]], default: 'jenkins'
property :jvm_options, String
property :java_path, String

# JNLP-specific properties
property :group, String, default: 'jenkins',
                         regex: [Chef::Config[:group_valid_regex]]
property :service_name, String, default: 'jenkins-slave'
property :service_groups, Array,
         default: lazy { |r| [r.group] }

# Criteo-specific: additional groups for the service user
property :supplementary_groups, Array, default: []

# Criteo-specific: checksum for slave.jar verification
property :checksum, String

deprecated_property_alias 'runit_groups', 'service_groups',
  '`runit_groups` was renamed to `service_groups` with the move to systemd services'

load_current_value do
  current_slave_data = current_slave_from_jenkins

  if current_slave_data
    slave_name current_slave_data[:name]
    description current_slave_data[:description]
    remote_fs current_slave_data[:remote_fs]
    executors current_slave_data[:executors]
    labels current_slave_data[:labels]

    @exists = true
    @connected = current_slave_data[:connected]
    @online = current_slave_data[:online]
  else
    current_value_does_not_exist!
  end
end

action :create do
  do_create

  directory ::File.expand_path(new_resource.remote_fs, '..') do
    recursive true
    action :create
  end

  unless platform?('windows')
    group new_resource.group do
      system node['jenkins']['master']['use_system_accounts']
    end

    user new_resource.user do
      gid new_resource.group
      comment 'Jenkins agent user - Created by Chef'
      home new_resource.remote_fs
      system node['jenkins']['master']['use_system_accounts']
      action :create
    end
  end

  directory new_resource.remote_fs do
    owner new_resource.user
    group new_resource.group
    recursive true
    action :create
  end

  remote_file slave_jar do
    source slave_jar_url
    backup(false)
    mode('0755')
    atomic_update(false)
    notifies :restart, "systemd_unit[#{new_resource.service_name}.service]" unless platform?('windows')
  end

  return if platform?('windows')

  create_systemd_service
end

action :delete do
  do_delete
end

action :connect do
  if current_resource && connected?
    Chef::Log.debug("#{new_resource} already connected - skipping")
  else
    converge_by("Connect #{new_resource}") do
      executor.execute!('connect-node', escape(new_resource.slave_name))
    end
  end
end

action :disconnect do
  if connected?
    converge_by("Disconnect #{new_resource}") do
      executor.execute!('disconnect-node', escape(new_resource.slave_name))
    end
  else
    Chef::Log.debug("#{new_resource} already disconnected - skipping")
  end
end

action :online do
  if current_resource && online?
    Chef::Log.debug("#{new_resource} already online - skipping")
  else
    converge_by("Online #{new_resource}") do
      executor.execute!('online-node', escape(new_resource.slave_name))
    end
  end
end

action :offline do
  if online?
    converge_by("Offline #{new_resource}") do
      command_pieces = [escape(new_resource.slave_name)]
      command_pieces << "-m '#{escape(new_resource.offline_reason)}'" if new_resource.offline_reason
      executor.execute!('offline-node', command_pieces)
    end
  else
    Chef::Log.debug("#{new_resource} already offline - skipping")
  end
end

action_class do
  include Jenkins::Helper

  def exists?
    !@exists.nil? && @exists
  end

  def connected?
    !@connected.nil? && @connected
  end

  def online?
    !@online.nil? && @online
  end

  def merge_preserved_labels!
    if current_resource
      new_resource.labels |= current_resource.labels.select { |i| i[/^prsrv_/] }
    end
  end

  def slave_jar
    @slave_jar ||= ::File.join(new_resource.remote_fs, 'slave.jar')
  end

  def slave_jar_url
    @slave_jar_url ||= uri_join(endpoint, 'jnlpJars', 'slave.jar')
  end

  def slave_jar_checksum
    new_resource.checksum
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

  def jnlp_secret
    return @jnlp_secret if @jnlp_secret
    json = executor.groovy! <<~GROOVY
      output = [
        secret:jenkins.slaves.JnlpSlaveAgentProtocol.SLAVE_SECRET.mac('#{new_resource.slave_name}')
      ]

      builder = new groovy.json.JsonBuilder(output)
      println(builder)
    GROOVY
    output = JSON.parse(json, symbolize_names: true)
    @jnlp_secret = output[:secret]
  end

  def java
    new_resource.java_path || node['jenkins']['java'] || 'java'
  end

  def create_systemd_service
    exec_string = "#{java} #{new_resource.jvm_options}"
    exec_string << " -cp #{slave_jar} hudson.remoting.jnlp.Main"
    exec_string << ' -headless'
    exec_string << " -workDir #{new_resource.remote_fs}"
    exec_string << " -direct #{jnlp_direct_host}:#{jnlp_direct_port}"
    exec_string << ' -protocols JNLP4-connect'
    exec_string << " -instanceIdentity #{instance_identity} #{jnlp_secret} #{new_resource.slave_name}"

    supplementary_groups = (new_resource.supplementary_groups + new_resource.service_groups).uniq.reject { |g| g == new_resource.group }

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
        #{supplementary_groups.empty? ? '' : "SupplementaryGroups=#{supplementary_groups.join(' ')}"}
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

  def do_create
    merge_preserved_labels!
    if current_resource && correct_config?
      Chef::Log.info("#{new_resource} exists - skipping")
    else
      converge_by("Create #{new_resource}") do
        executor.groovy! <<-EOH.gsub(/^ {10}/, '')
          import hudson.model.*
          import hudson.slaves.*
          import jenkins.model.*
          import jenkins.slaves.*

          props = []
          availability = #{convert_to_groovy(new_resource.availability)}
          usage_mode = #{convert_to_groovy(new_resource.usage_mode)}
          env_map = #{convert_to_groovy(new_resource.environment)}
          labels = #{convert_to_groovy(new_resource.labels.sort.join(' '))}

          if (usage_mode == 'normal') {
            mode = Node.Mode.NORMAL
          } else {
            mode = Node.Mode.EXCLUSIVE
          }

          if (availability == 'demand') {
            retention_strategy = new RetentionStrategy.Demand(
              #{new_resource.in_demand_delay},
              #{new_resource.idle_delay}
            )
          } else if (availability == 'always') {
            retention_strategy = new RetentionStrategy.Always()
          } else {
            retention_strategy = RetentionStrategy.NOOP
          }

          if (env_map != null) {
            env_vars = new hudson.EnvVars(env_map)
            entries = env_vars.collect {
              k,v -> new EnvironmentVariablesNodeProperty.Entry(k,v)
            }
            props << new EnvironmentVariablesNodeProperty(entries)
          }

          launcher = new hudson.slaves.JNLPLauncher()

          slave = new DumbSlave(
            #{convert_to_groovy(new_resource.name)},
            #{convert_to_groovy(new_resource.description)},
            #{convert_to_groovy(new_resource.remote_fs)},
            #{convert_to_groovy(new_resource.executors.to_s)},
            mode,
            labels,
            launcher,
            retention_strategy,
            props
          )

          nodes = new ArrayList(Jenkins.instance.getNodes())
          ix = nodes.indexOf(slave)
          (ix >= 0) ? nodes.set(ix, slave) : nodes.add(slave)
          Jenkins.instance.setNodes(nodes)
        EOH
      end
    end
  end

  def do_delete
    if current_resource
      converge_by("Delete #{new_resource}") do
        executor.execute!('delete-node', escape(new_resource.slave_name))
      end
    else
      Chef::Log.debug("#{new_resource} does not exist - skipping")
    end
  end

  def current_slave_from_jenkins
    return @current_slave if @current_slave

    Chef::Log.debug "Load #{new_resource} agent information"

    json = executor.groovy! <<-EOH.gsub(/^ {6}/, '')
      import hudson.model.*
      import hudson.slaves.*
      import jenkins.model.*
      import jenkins.slaves.*

      slave = Jenkins.instance.getNode('#{new_resource.slave_name}') as Slave

      if(slave == null) {
        return null
      }

      def slave_environment = null
      slave_env_vars = slave.nodeProperties.get(EnvironmentVariablesNodeProperty.class)?.envVars
      if (slave_env_vars)
        slave_environment = new java.util.HashMap<String,String>(slave_env_vars)

      current_slave = [
        name:slave.name,
        description:slave.nodeDescription,
        remote_fs:slave.remoteFS,
        executors:slave.numExecutors.toInteger(),
        usage_mode:slave.mode.toString().toLowerCase(),
        labels:slave.labelString.split().sort(),
        environment:slave_environment,
        connected:(slave.computer.connectTime > 0),
        online:slave.computer.online
      ]

      if (slave.retentionStrategy instanceof RetentionStrategy.Always) {
        current_slave['availability'] = 'always'
      } else if (slave.retentionStrategy instanceof RetentionStrategy.Demand) {
        current_slave['availability'] = 'demand'
        retention = slave.retentionStrategy as RetentionStrategy.Demand
        current_slave['in_demand_delay'] = retention.inDemandDelay
        current_slave['idle_delay'] = retention.idleDelay
      } else {
        current_slave['availability'] = null
      }

      builder = new groovy.json.JsonBuilder(current_slave)
      println(builder)
    EOH

    return if json.nil? || json.empty?

    @current_slave = JSON.parse(json, symbolize_names: true)
    @current_slave = convert_blank_values_to_nil(@current_slave)
  end

  def correct_config?
    wanted_slave = {
      name: new_resource.slave_name,
      description: new_resource.description,
      remote_fs: new_resource.remote_fs,
      executors: new_resource.executors,
      usage_mode: new_resource.usage_mode,
      labels: new_resource.labels.sort,
      availability: new_resource.availability,
      environment: new_resource.environment,
    }

    if new_resource.availability.to_s == 'demand'
      wanted_slave[:in_demand_delay] = new_resource.in_demand_delay
      wanted_slave[:idle_delay] = new_resource.idle_delay
    end

    current_slave_from_jenkins.dup.tap do |c|
      c.delete(:connected)
      c.delete(:online)
    end == wanted_slave
  end
end
