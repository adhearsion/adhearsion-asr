module AdhearsionASR
  class Plugin < Adhearsion::Plugin
    config :adhearsion_asr do
      auto_include true, transform: Proc.new { |v| v == 'true' }, desc: "Enable or disable auto inclusion of overridden Adhearsion Core methods in all call controllers."
      min_confidence 0.5, desc: 'The default minimum confidence level used for all recognizer invocations.', transform: Proc.new { |v| v.to_f }
      timeout 5, desc: 'The default timeout (in seconds) used for all recognizer invocations.', transform: Proc.new { |v| v.to_i }
      inter_digit_timeout 2, desc: 'The timeout used between DTMF digits and to terminate partial invocations', transform: Proc.new { |v| v.to_i }
      sensitivity 0.5, desc: 'The sensitivity of speech recognition. Valid values between 0 and 1.', transform: Proc.new { |v| v.to_f }
      recognizer nil, desc: 'The default recognizer used for all input. Set nil to use platform default.'
      input_language 'en-US', desc: 'The default language set on generated grammars. Set nil to use platform default.'
    end

    init do
      if config[:auto_include]
        ::Adhearsion::CallController.mixin ::AdhearsionASR::ControllerMethods
      end
    end
  end
end
