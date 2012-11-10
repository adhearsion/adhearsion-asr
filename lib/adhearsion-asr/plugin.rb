module AdhearsionASR
  class Plugin < Adhearsion::Plugin
    config :adhearsion_asr do
      min_confidence 0.5, desc: 'The default minimum confidence level used for all recognizer invocations.'
    end
  end
end
