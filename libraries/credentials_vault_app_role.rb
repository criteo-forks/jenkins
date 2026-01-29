#
# Cookbook:: jenkins
# Resource:: credentials_vault_app_role
#
# Author:: Guillaume Monceyron <g.monceyron@criteo.com>
#
# Copyright:: 2026, Criteo
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

require_relative 'credentials'

class Chef
  class Resource::JenkinsVaultAppRoleCredentials < Resource::JenkinsCredentials
    resource_name :jenkins_vault_app_role_credentials # Still needed for Chef 15 and below
    provides :jenkins_vault_app_role_credentials

    # Chef attributes
    identity_attr :description

    # Attributes
    attribute :description,
              kind_of: String
    attribute :role_id,
              kind_of: String,
              required: true
    attribute :secret_id,
              kind_of: String,
              required: true
    attribute :path,
              kind_of: String,
              default: 'approle'
    attribute :use_policies,
              kind_of: [TrueClass, FalseClass],
              default: true
  end
end

class Chef
  class Provider::JenkinsVaultAppRoleCredentials < Provider::JenkinsCredentials
    provides :jenkins_vault_app_role_credentials

    def load_current_resource
      @current_resource ||= Resource::JenkinsVaultAppRoleCredentials.new(new_resource.name)

      super

      if current_credentials
        @current_resource.role_id(current_credentials[:role_id])
        @current_resource.secret_id(current_credentials[:secret_id])
        @current_resource.path(current_credentials[:path])
        @current_resource.use_policies(current_credentials[:use_policies])
      end

      @current_resource
    end

    private

    #
    # @see Chef::Resource::JenkinsCredentials#credentials_groovy
    # @see https://github.com/jenkinsci/hashicorp-vault-plugin/blob/master/src/main/java/com/datapipe/jenkins/vault/credentials/VaultAppRoleCredential.java
    #
    def credentials_groovy
      <<-EOH.gsub(/^ {8}/, '')
        import hudson.util.Secret
        import com.cloudbees.plugins.credentials.CredentialsScope
        import com.datapipe.jenkins.vault.credentials.VaultAppRoleCredential

        credentials = new VaultAppRoleCredential(
          CredentialsScope.GLOBAL,
          #{convert_to_groovy(new_resource.id)},
          #{convert_to_groovy(new_resource.description)},
          #{convert_to_groovy(new_resource.role_id)},
          Secret.fromString(#{convert_to_groovy(new_resource.secret_id)}),
          #{convert_to_groovy(new_resource.path)}
        )
        credentials.setUsePolicies(#{new_resource.use_policies})
      EOH
    end

    #
    # @see Chef::Resource::JenkinsCredentials#fetch_credentials_groovy
    #
    def fetch_existing_credentials_groovy(groovy_variable_name)
      <<-EOH.gsub(/^ {8}/, '')
        #{credentials_for_id_groovy(new_resource.id, groovy_variable_name)}
      EOH
    end

    #
    # @see Chef::Resource::JenkinsCredentials#resource_attributes_groovy
    #
    def resource_attributes_groovy(groovy_variable_name)
      <<-EOH.gsub(/^ {8}/, '')
        #{groovy_variable_name} = [
          id:credentials.id,
          description:credentials.description,
          role_id:credentials.roleId,
          secret_id:credentials.secretId,
          path:credentials.path,
          use_policies:credentials.usePolicies
        ]
      EOH
    end

    #
    # @see Chef::Resource::JenkinsCredentials#attribute_to_property_map
    #
    def attribute_to_property_map
      { secret_id: 'credentials.secretId.plainText' }
    end

    #
    # @see Chef::Resource::JenkinsCredentials#correct_config?
    #
    def correct_config?
      wanted_credentials = {
        description: new_resource.description,
        role_id: new_resource.role_id,
        secret_id: new_resource.secret_id,
        path: new_resource.path,
        use_policies: new_resource.use_policies,
      }

      # Don't compare the ID as it is generated
      current_credentials.dup.tap { |c| c.delete(:id) } == convert_blank_values_to_nil(wanted_credentials)
    end
  end
end
