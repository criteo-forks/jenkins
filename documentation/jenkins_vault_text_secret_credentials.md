# jenkins_vault_text_secret_credentials

Vault Text Secret credentials for the `hashicorp-vault-plugin`. This credential type lets Jenkins expose a single text value read from a HashiCorp Vault KV secret.

## Requirements

Requires the `hashicorp-vault-plugin` to be installed on your Jenkins instance.

## Examples

```ruby
# Create Vault Text Secret credentials
jenkins_vault_text_secret_credentials 'vault-password' do
  id 'vault-password'
  description 'Password read from Vault'
  path 'secret/jenkins/passwords'
  vault_key 'password'
end

# Create Vault Text Secret credentials with all Vault lookup options
jenkins_vault_text_secret_credentials 'namespaced-vault-password' do
  id 'namespaced-vault-password'
  description 'Password read from a namespaced Vault mount'
  path 'secret/jenkins/passwords'
  prefix_path 'kv'
  namespace 'admin'
  engine_version 2
  vault_key 'password'
end

# Delete Vault Text Secret credentials
jenkins_vault_text_secret_credentials 'vault-password' do
  id 'vault-password'
  path 'secret/jenkins/passwords'
  action :delete
end
```

## Properties

- **id** - (required) The unique identifier for the credential.
- **description** - (optional) A human-readable description of the credential.
- **path** - (required) The Vault secret path to read.
- **prefix_path** - (optional) A Vault path prefix for installations using prefixed KV mounts.
- **namespace** - (optional) The Vault namespace.
- **engine_version** - (optional) The Vault KV engine version. Defaults to `2`.
- **vault_key** - (optional) The key inside the Vault secret. Defaults to `'secret'`.

## Scopes

Credentials in Jenkins can be created with 2 different "scopes" which determines where the credentials can be used:

- **GLOBAL** - This credential is available to the object on which the credential is associated and all objects that are children of that object. Typically you would use global-scoped credentials for things that are needed by jobs.
- **SYSTEM** - This credential is only available to the object on which the credential is associated. Typically you would use system-scoped credentials for things like email auth, slave connection, etc, i.e. where the Jenkins instance itself is using the credential. Unlike the global scope, this significantly restricts where the credential can be used, thereby providing a higher degree of confidentiality to the credential.

The credentials created with the `jenkins_vault_text_secret_credentials` resource are assigned a `GLOBAL` scope.
