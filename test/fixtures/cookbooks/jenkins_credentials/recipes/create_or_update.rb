include_recipe 'jenkins_server_wrapper::default'

jenkins_password_credentials 'schisamo' do
  id 'schisamo'
  description 'passwords are for suckers'
  username 'schisamo'
  password 'superseekret'
end

jenkins_password_credentials 'schisamo' do
  id 'schisamo'
  description 'passwords are for suckers'
  username 'schisamoschisamo'
  password 'superseekretsuperseekret'
end
