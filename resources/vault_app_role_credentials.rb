require 'json'

unified_mode true

resource_name :jenkins_vault_app_role_credentials
provides :jenkins_vault_app_role_credentials

property :id, String, name_property: true
property :description, String,
         default: lazy { |r| "Vault AppRole #{r.id} - created by Chef" }
property :role_id, String, required: true
property :secret_id, String, required: true, sensitive: true
property :path, String, default: 'approle'
property :use_policies, [true, false], default: true
property :namespace, String
property :skip_ssl_verification, [true, false], default: false
property :timeout, Integer, default: 30

def initialize(name, run_context = nil)
  super
  @sensitive = true
end

load_current_value do
  current_creds = current_credentials_from_jenkins

  if current_creds
    id current_creds[:id]
    description current_creds[:description]
    role_id current_creds[:role_id]
    secret_id current_creds[:secret_id] if current_creds[:secret_id]
    path current_creds[:path]
    use_policies current_creds[:use_policies]
  else
    current_value_does_not_exist!
  end
end

action :create do
  if current_resource && correct_config?
    Chef::Log.info("#{new_resource} exists - skipping")
  else
    converge_by("Create #{new_resource}") do
      executor.groovy! <<-EOH.gsub(/^ {8}/, '')
        import hudson.util.Secret
        import com.cloudbees.plugins.credentials.CredentialsScope
        import com.datapipe.jenkins.vault.credentials.VaultAppRoleCredential

        global_domain = com.cloudbees.plugins.credentials.domains.Domain.global()
        credentials_store =
          Jenkins.instance.getExtensionList(
            'com.cloudbees.plugins.credentials.SystemCredentialsProvider'
          )[0].getStore()

        credentials = new VaultAppRoleCredential(
          CredentialsScope.GLOBAL,
          #{convert_to_groovy(new_resource.id)},
          #{convert_to_groovy(new_resource.description)},
          #{convert_to_groovy(new_resource.role_id)},
          Secret.fromString(#{convert_to_groovy(new_resource.secret_id)}),
          #{convert_to_groovy(new_resource.path)}
        )
        credentials.setUsePolicies(#{new_resource.use_policies})

        #{credentials_for_id_groovy(new_resource.id, 'existing_credentials')}

        if(existing_credentials != null) {
          credentials_store.updateCredentials(
            global_domain,
            existing_credentials,
            credentials
          )
        } else {
          credentials_store.addCredentials(global_domain, credentials)
        }
      EOH
    end
  end
end

action :delete do
  if current_resource
    converge_by("Delete #{new_resource}") do
      executor.groovy! <<-EOH.gsub(/^ {8}/, '')
        import jenkins.model.*
        import com.cloudbees.plugins.credentials.*;

        global_domain = com.cloudbees.plugins.credentials.domains.Domain.global()
        credentials_store =
          Jenkins.instance.getExtensionList(
            'com.cloudbees.plugins.credentials.SystemCredentialsProvider'
          )[0].getStore()

        #{credentials_for_id_groovy(new_resource.id, 'existing_credentials')}

        if(existing_credentials != null) {
          credentials_store.removeCredentials(
            global_domain,
            existing_credentials
          )
        }
      EOH
    end
  else
    Chef::Log.debug("#{new_resource} does not exist - skipping")
  end
end

action_class do
  include Jenkins::Helper
  include Jenkins::CredentialsHelpers

  def current_credentials_from_jenkins
    return @current_credentials if @current_credentials

    Chef::Log.debug "Load #{new_resource} credentials information"

    json = executor.groovy! <<-EOH.gsub(/^ {6}/, '')
      import com.datapipe.jenkins.vault.credentials.VaultAppRoleCredential

      #{credentials_for_id_groovy(new_resource.id, 'credentials')}

      if(credentials == null) {
        return null
      }

      current_credentials = [
        id:credentials.id,
        description:credentials.description,
        role_id:credentials.roleId,
        secret_id:credentials.secretId,
        path:credentials.path,
        use_policies:credentials.usePolicies
      ]

      builder = new groovy.json.JsonBuilder(current_credentials)
      println(builder)
    EOH

    return if json.nil? || json.empty?

    @current_credentials = JSON.parse(json, symbolize_names: true)
    @current_credentials = convert_blank_values_to_nil(@current_credentials)
  end

  def correct_config?
    wanted_credentials = {
      description: new_resource.description,
      role_id: new_resource.role_id,
      secret_id: new_resource.secret_id,
      path: new_resource.path,
      use_policies: new_resource.use_policies,
    }

    current_credentials_from_jenkins.dup.tap { |c| c.delete(:id) } == convert_blank_values_to_nil(wanted_credentials)
  end
end
