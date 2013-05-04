require 'adhearsion-asr/result'

module AdhearsionASR
  class PromptBuilder
    def initialize(output_document, grammars, options)
      output_options = {
        render_document: {value: output_document},
        renderer: Plugin.config.renderer
      }.merge(options[:output_options] || {})

      input_options = {
        mode: :dtmf,
        initial_timeout: (options[:timeout] || Plugin.config.timeout) * 1000,
        inter_digit_timeout: (options[:timeout] || Plugin.config.timeout) * 1000,
        max_silence: (options[:timeout] || Plugin.config.timeout) * 1000,
        min_confidence: Plugin.config.min_confidence,
        grammars: grammars,
        recognizer: Plugin.config.recognizer,
        language: Plugin.config.input_language,
        terminator: options[:terminator]
      }.merge(options[:input_options] || {})

      @prompt = Punchblock::Component::Prompt.new output_options, input_options, barge_in: options.has_key?(:interruptible) ? options[:interruptible] : true
    end

    def execute(controller)
      controller.execute_component_and_await_completion @prompt

      result @prompt.complete_event.reason
    end

    private

    def result(reason)
      Result.new.tap do |result|
        case reason
        when proc { |r| r.respond_to? :nlsml }
          result.status         = :match
          result.confidence     = reason.confidence
          result.response       = reason.utterance
          result.interpretation = reason.interpretation
          result.nlsml          = reason.nlsml
        when Punchblock::Event::Complete::Error
          raise Error, reason.details
        when Punchblock::Event::Complete::Reason
          result.status = reason.name
        else
          raise "Unknown completion reason received: #{reason}"
        end
        logger.debug "Ask completed with result #{result.inspect}"
      end
    end
  end
end
