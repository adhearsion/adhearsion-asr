module AdhearsionASR
  Error = Class.new StandardError
  ListenError = Class.new Error
end

require "adhearsion-asr/version"
require "adhearsion-asr/plugin"
require "adhearsion-asr/controller_methods"
