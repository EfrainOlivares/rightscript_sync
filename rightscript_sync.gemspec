Gem::Specification.new do |gem|
  gem.name        = 'rightscript_sync'
  gem.version     = '0.0.0'
  gem.executables = ['rightscript_sync']
  gem.summary     = 'Sync scripts on a drive to RightScale'
  gem.authors     = ['RightScale']
  gem.files       = `git ls-files`.split(' ')
  gem.platform    = Gem::Platform::RUBY
  gem.add_runtime_dependency 'thor'
  gem.add_runtime_dependency 'terminal-table'
  gem.add_runtime_dependency 'right_api_client', '~> 1.5.26'
  gem.add_development_dependency 'pry'
  gem.add_development_dependency 'rake'
end
