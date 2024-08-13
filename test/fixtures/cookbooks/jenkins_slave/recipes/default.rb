include_recipe '::create_jnlp'
include_recipe '::delete_jnlp'

return if docker? # Agent connection does not work

include_recipe '::create_ssh'

include_recipe '::connect'
include_recipe '::online'

include_recipe '::offline'
include_recipe '::disconnect'

include_recipe '::delete_ssh'
