# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "adhearsion-asr/version"

Gem::Specification.new do |s|
  s.name        = "adhearsion-asr"
  s.version     = AdhearsionASR::VERSION
  s.authors     = ["Ben Langfeld"]
  s.email       = ["ben@langfeld.me"]
  s.homepage    = "https://github.com/adhearsion/adhearsion-asr"
  s.summary     = %q{Adds speech recognition support to Adhearsion as a plugin}
  s.description = %q{Adds speech recognition support to Adhearsion as a plugin}

  s.rubyforge_project = "adhearsion-asr"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.require_paths = ["lib"]

  s.add_runtime_dependency %q<adhearsion>, ["~> 2.1"]

  s.add_development_dependency %q<bundler>, ["~> 1.0"]
  s.add_development_dependency %q<rspec>, ["~> 2.5"]
  s.add_development_dependency %q<rake>, [">= 0"]
  s.add_development_dependency %q<guard-rspec>
  s.add_development_dependency %q<rb-fsevent>, ['~> 0.9']
 end
