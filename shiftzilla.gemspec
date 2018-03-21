# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'shiftzilla/version'

Gem::Specification.new do |spec|
  spec.name          = "shiftzilla"
  spec.version       = Shiftzilla::VERSION
  spec.authors       = ["N. Harrison Ripps"]
  spec.email         = ["nhr@redhat.com"]
  spec.summary       = %q{Shiftzilla is a tool for providing historical reports based on Bugzilla data}
  spec.description   = spec.summary
  spec.homepage      = "http://github.com/nhr/shiftzilla"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency 'bundler', '~> 1.16', '>= 1.16.1'

  spec.add_dependency 'fileutils',      '~> 1.0', '>= 1.0.2'
  spec.add_dependency 'haml',           '~> 5.0', '>= 5.0.4'
  spec.add_dependency 'highline',       '~> 1.7', '>= 1.7.10'
  spec.add_dependency 'sqlite3',        '~> 1.3', '>= 1.3.13'
  spec.add_dependency 'terminal-table', '~> 1.8'
  spec.add_dependency 'trollop',        '~> 2.1', '>= 2.1.2'
end
