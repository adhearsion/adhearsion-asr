module AdhearsionASR
  class Plugin < Adhearsion::Plugin
    config :adhearsion_asr do
      min_confidence 0.5, desc: 'The default minimum confidence level used for all recognizer invocations.', transform: Proc.new { |v| v.to_f }
      timeout 5, desc: 'The default timeout (in seconds) used for all recognizer invocations.', transform: Proc.new { |v| v.to_i }
    end
  end
end
