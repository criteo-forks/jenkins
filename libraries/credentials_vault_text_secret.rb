#
# Cookbook:: jenkins
# Resource:: credentials_vault_text_secret
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
  class Resource::JenkinsVaultTextSecretCredentials < Resource::JenkinsCredentials
    resource_name :jenkins_vault_text_secret_credentials # Still needed for Chef 15 and below
    provides :jenkins_vault_text_secret_credentials

    # Chef attributes
    identity_attr :description

    # Attributes
    attribute :description,
              kind_of: String
    attribute :path,
              kind_of: String,
              required: true
    attribute :prefix_path,
              kind_of: String
    attribute :namespace,
              kind_of: String
    attribute :engine_version,
              kind_of: Integer,
              equal_to: [1, 2],
              default: 2
    attribute :vault_key,
              kind_of: String,
              default: 'secret'
  end
end

class Chef
  class Provider::JenkinsVaultTextSecretCredentials < Provider::JenkinsCredentials
    provides :jenkins_vault_text_secret_credentials

    def load_current_resource
      @current_resource ||= Resource::JenkinsVaultTextSecretCredentials.new(new_resource.name)

      super

      if current_credentials
        @current_resource.path(current_credentials[:path])
        @current_resource.prefix_path(current_credentials[:prefix_path])
        @current_resource.namespace(current_credentials[:namespace])
        @current_resource.engine_version(current_credentials[:engine_version])
        @current_resource.vault_key(current_credentials[:vault_key])
      end

      @current_resource
    end

    private

    #
    # @see Chef::Resource::JenkinsCredentials#credentials_groovy
    # @see https://github.com/jenkinsci/hashicorp-vault-plugin/blob/master/src/main/java/com/datapipe/jenkins/vault/credentials/common/VaultStringCredentialImpl.java
    #
    def credentials_groovy
      <<-EOH.gsub(/^ {8}/, '')
        import com.cloudbees.plugins.credentials.CredentialsScope
        import com.datapipe.jenkins.vault.credentials.common.VaultStringCredentialImpl

        credentials = new VaultStringCredentialImpl(
          CredentialsScope.GLOBAL,
          #{convert_to_groovy(new_resource.id)},
          #{convert_to_groovy(new_resource.description)}
        )
        credentials.setPath(#{convert_to_groovy(new_resource.path)})
        credentials.setVaultKey(#{convert_to_groovy(new_resource.vault_key)})
        credentials.setEngineVersion(#{convert_to_groovy(new_resource.engine_version)})
        #{optional_setter_groovy('setPrefixPath', new_resource.prefix_path)}
        #{optional_setter_groovy('setNamespace', new_resource.namespace)}
      EOH
    end

    #
    # @see Chef::Resource::JenkinsCredentials#fetch_credentials_groovy
    #
    def fetch_existing_credentials_groovy(groovy_variable_name)
      <<-EOH.gsub(/^ {8}/, '')
        import jenkins.model.Jenkins
        import com.cloudbees.plugins.credentials.CredentialsMatchers
        import com.cloudbees.plugins.credentials.CredentialsProvider
        import com.cloudbees.plugins.credentials.common.IdCredentials

        id_matcher = CredentialsMatchers.withId(#{convert_to_groovy(new_resource.id)})
        available_credentials =
          CredentialsProvider.lookupCredentials(
            IdCredentials.class,
            Jenkins.getInstance(),
            hudson.security.ACL.SYSTEM
          )

        #{groovy_variable_name} =
          CredentialsMatchers.firstOrNull(
            available_credentials,
            id_matcher
          )
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
          path:credentials.path,
          prefix_path:credentials.prefixPath,
          namespace:credentials.namespace,
          engine_version:credentials.engineVersion,
          vault_key:credentials.vaultKey
        ]
      EOH
    end

    #
    # @see Chef::Resource::JenkinsCredentials#correct_config?
    #
    def correct_config?
      wanted_credentials = {
        description: new_resource.description,
        path: new_resource.path,
        prefix_path: new_resource.prefix_path,
        namespace: new_resource.namespace,
        engine_version: new_resource.engine_version,
        vault_key: new_resource.vault_key,
      }

      # Don't compare the ID as it is generated
      current_credentials.dup.tap { |c| c.delete(:id) } == convert_blank_values_to_nil(wanted_credentials)
    end

    def optional_setter_groovy(setter, value)
      return if value.nil?

      "credentials.#{setter}(#{convert_to_groovy(value)})"
    end
  end
end
