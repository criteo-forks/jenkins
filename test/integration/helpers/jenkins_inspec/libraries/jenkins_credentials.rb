#
# Custom jenkins_credentials matcher
#

class JenkinsCredentials < Inspec.resource(1)
  require 'openssl'
  require 'rexml/document'
  require 'rexml/xpath'

  name 'jenkins_credentials'

  attr_reader :username

  def initialize(username)
    @username = username
  end

  def exist?
    !xml.nil?
  end

  def id
    try { xml.elements['id'].text }
  end

  def to_s
    "Jenkins Credentails #{username}"
  end

  private

  def doc
    @doc ||= begin
      f = inspec.backend.file('/var/lib/jenkins/credentials.xml')
      return unless f.file?

      REXML::Document.new(f.content)
    end
  end

  def try(&_block)
    yield
  rescue NoMethodError
    nil
  end
end

# rubocop:disable Naming/PredicateName
class JenkinsUserCredentials < JenkinsCredentials
  attr_reader :username

  name 'jenkins_user_credentials'

  def initialize(username)
    @username = username
  end

  def description
    try { xml.elements['description'].text }
  end

  def has_password?
    !!(try { xml.elements['password'].text })
  end

  def has_private_key?
    !!xml.elements['privateKeySource/privateKey'].text
  end

  def has_passphrase?
    !!(try { xml.elements['passphrase'].text })
  end

  def to_s
    "Jenkins User Credentails #{username}"
  end

  private

  def xml
    return @xml if @xml

    @xml = REXML::XPath.first(doc, "//*[username/text() = '#{username}' and scope/text() = 'GLOBAL']/")
  rescue Errno::ENOENT
    @xml = nil
  end
end

class JenkinsSecretTextCredentials < JenkinsCredentials
  attr_reader :description

  name 'jenkins_secret_text_credentials'

  def initialize(description)
    @description = description
  end

  def secret
    try { xml.elements['secret'].text }
  end

  def to_s
    "Jenkins Text Credentails #{description}"
  end

  private

  def xml
    return @xml if @xml

    @xml = REXML::XPath.first(doc, "//*[description/text() = '#{description}']/")
  rescue Errno::ENOENT
    @xml = nil
  end
end

class JenkinsVaultTextSecretCredentials < JenkinsCredentials
  attr_reader :credential_id

  name 'jenkins_vault_text_secret_credentials'

  def initialize(credential_id)
    @credential_id = credential_id
  end

  def description
    try { xml.elements['description'].text }
  end

  def path
    try { xml.elements['path'].text }
  end

  def prefix_path
    try { xml.elements['prefixPath'].text }
  end

  def namespace
    try { xml.elements['namespace'].text }
  end

  def engine_version
    try { xml.elements['engineVersion'].text.to_i }
  end

  def vault_key
    try { xml.elements['vaultKey'].text }
  end

  def to_s
    "Jenkins Vault Text Secret Credentials #{credential_id}"
  end

  private

  def xml
    return @xml if @xml

    @xml = REXML::XPath.first(doc, "//*[id/text() = '#{credential_id}' and scope/text() = 'GLOBAL']/")
  rescue Errno::ENOENT
    @xml = nil
  end
end
