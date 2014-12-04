require 'adhearsion-asr/result'

module AdhearsionASR
  class PromptBuilder
    def initialize(output_document, grammars, options)
      input_options = {
        mode: options[:mode] || :dtmf,
        initial_timeout: timeout(options[:timeout] || Plugin.config.timeout),
        inter_digit_timeout: timeout(options[:timeout] || Plugin.config.timeout),
        max_silence: timeout(options[:timeout] || Plugin.config.timeout),
        min_confidence: Plugin.config.min_confidence,
        grammars: grammars,
        recognizer: Plugin.config.recognizer,
        language: Plugin.config.input_language,
        terminator: options[:terminator]
      }.merge(options[:input_options] || {})

      @prompt = if output_document
        output_options = {
          render_document: {value: output_document},
          renderer: Adhearsion.config.platform.media.default_renderer,
          voice: Adhearsion.config.platform.media.default_voice
        }.merge(options[:output_options] || {})

        Punchblock::Component::Prompt.new output_options, input_options, barge_in: options.has_key?(:interruptible) ? options[:interruptible] : true
      else
        Punchblock::Component::Input.new input_options
      end
    end

    def execute(controller)
      controller.execute_component_and_await_completion @prompt

      result @prompt.complete_event.reason
    rescue Adhearsion::Call::ExpiredError
      raise Adhearsion::Call::Hangup
    end

    private

    def result(reason)
      Result.new.tap do |result|
        case reason
        when proc { |r| r.respond_to? :nlsml }
          result.status         = :match
          result.mode           = reason.mode
          result.confidence     = reason.confidence
          result.utterance      = reason.utterance
          result.interpretation = reason.interpretation
          result.nlsml          = reason.nlsml
        when Punchblock::Event::Complete::Error
          raise Error, reason.details
        when Punchblock::Component::Input::Complete::NoMatch
          result.status = :nomatch
        when Punchblock::Component::Input::Complete::NoInput
          result.status = :noinput
        when Punchblock::Event::Complete::Hangup
          result.status = :hangup
        when Punchblock::Event::Complete::Stop
          result.status = :stop
        else
          raise "Unknown completion reason received: #{reason}"
        end
        logger.debug "Ask completed with result #{result.inspect}"
      end
    end

    def timeout(value)
      value > 0 ? value * 1000 : value
    end
  end
end
