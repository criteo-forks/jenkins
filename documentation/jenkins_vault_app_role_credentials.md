# jenkins_vault_app_role_credentials

HashiCorp Vault App Role credentials for the `hashicorp-vault-plugin`. This credential type allows Jenkins to authenticate with Vault using the AppRole authentication method.

## Requirements

Requires the `hashicorp-vault-plugin` to be installed on your Jenkins instance.

## Examples

```ruby
# Create Vault App Role credentials
jenkins_vault_app_role_credentials 'vault-approle' do
  id          'vault-approle-creds'
  description 'Vault AppRole credentials for Jenkins'
  role_id     'my-role-id'
  secret_id   'my-secret-id'
  path        'approle'  # Optional, defaults to 'approle'
end
```

```ruby
# Create Vault App Role credentials with custom path
jenkins_vault_app_role_credentials 'vault-jenkins' do
  id          'vault-jenkins-creds'
  description 'Vault AppRole credentials with custom path'
  role_id     'jenkins-role-id'
  secret_id   'jenkins-secret-id'
  path        'jenkins'
end
```

```ruby
# Delete Vault App Role credentials
jenkins_vault_app_role_credentials 'vault-approle' do
  id     'vault-approle-creds'
  action :delete
end
```

## Properties

- **id** - (required) The unique identifier for the credential. If not specified, a UUID will be generated.
- **description** - (optional) A human-readable description of the credential.
- **role_id** - (required) The Role ID used for AppRole authentication with Vault.
- **secret_id** - (required) The Secret ID used for AppRole authentication with Vault.
- **path** - (optional) The AppRole authentication mount path in Vault. Defaults to `'approle'`.

## About AppRole Authentication

AppRole is a Vault authentication method that is specifically designed for machine-to-machine authentication. It uses a `role_id` (similar to a username) and a `secret_id` (similar to a password) to authenticate.

When registering an AppRole auth backend in Vault, you can configure:
- How long the `secret_id` should live (can be indefinite)
- How often a token obtained via this backend can be used
- Which IP addresses can obtain a token using the `role_id` and `secret_id`
- And many more options

For more information, see the [HashiCorp Vault AppRole documentation](https://www.vaultproject.io/docs/auth/approle.html).

## Scopes

Credentials in Jenkins can be created with 2 different "scopes" which determines where the credentials can be used:

- **GLOBAL** - This credential is available to the object on which the credential is associated and all objects that are children of that object. Typically you would use global-scoped credentials for things that are needed by jobs.
- **SYSTEM** - This credential is only available to the object on which the credential is associated. Typically you would use system-scoped credentials for things like email auth, slave connection, etc, i.e. where the Jenkins instance itself is using the credential. Unlike the global scope, this significantly restricts where the credential can be used, thereby providing a higher degree of confidentiality to the credential.

The credentials created with the `jenkins_vault_app_role_credentials` resource are assigned a `GLOBAL` scope.
