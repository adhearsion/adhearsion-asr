module AdhearsionASR
  module ControllerMethods

    Result = Struct.new(:status, :confidence, :response, :interpretation, :nlsml) do
      def to_s
        response
      end

      def inspect
        "#<#{self.class} status=#{status.inspect}, confidence=#{confidence.inspect}, response=#{response.inspect}, interpretation=#{interpretation.inspect}, nlsml=#{nlsml.inspect}>"
      end
    end

    #
    # Prompts for input, handling playback of prompts, DTMF grammar construction, and execution
    #
    # @example A basic DTMF digit collection:
    #   ask "Welcome, ", "/opt/sounds/menu-prompt.mp3",
    #       timeout: 10, terminator: '#', limit: 3
    #
    # The first arguments will be a list of sounds to play, as accepted by #play, including strings for TTS, Date and Time objects, and file paths.
    # :timeout, :terminator and :limit options may be specified to automatically construct a grammar, or grammars may be manually specified.
    #
    # @param [Object, Array<Object>] args A list of outputs to play, as accepted by #play
    # @param [Hash] options Options to modify the grammar
    # @option options [Boolean] :interruptible If the prompt should be interruptible or not. Defaults to true
    # @option options [Integer] :limit Digit limit (causes collection to cease after a specified number of digits have been collected)
    # @option options [Integer] :timeout Timeout in seconds before the first and between each input digit
    # @option options [String] :terminator Digit to terminate input
    # @option options [RubySpeech::GRXML::Grammar, Array<RubySpeech::GRXML::Grammar>] :grammar One of a collection of grammars to execute
    # @option options [String, Array<String>] :grammar_url One of a collection of URLs for grammars to execute
    # @option options [Hash] :input_options A hash of options passed directly to the Punchblock Input constructor
    # @option options [Hash] :output_options A hash of options passed directly to the Punchblock Output constructor
    #
    # @return [Result] a result object from which the details of the response may be established
    #
    # @see Output#play
    # @see Punchblock::Component::Input.new
    # @see Punchblock::Component::Output.new
    #
    def ask(*args, &block)
      options = args.last.kind_of?(Hash) ? args.pop : {}
      prompts = args.flatten

      options[:grammar] || options[:grammar_url] || options[:limit] || options[:terminator] || raise(ArgumentError, "You must specify at least one of limit, terminator or grammar")

      grammars = []

      grammars.concat [options[:grammar]].flatten.compact.map { |val| {value: val} } if options[:grammar]
      grammars.concat [options[:grammar_url]].flatten.compact.map { |val| {url: val} } if options[:grammar_url]

      if grammars.empty?
        grammar = RubySpeech::GRXML.draw mode: :dtmf, root: 'digits' do
          rule id: 'digits', scope: 'public' do
            item repeat: "0-#{options[:limit]}" do
              one_of do
                0.upto(9) { |d| item { d.to_s } }
                item { "#" }
                item { "*" }
              end
            end
          end
        end
        grammars << {value: grammar}
      end

      output_options = {
        render_document: {value: output_formatter.ssml_for_collection(prompts)},
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

      prompt = Punchblock::Component::Prompt.new output_options, input_options, barge_in: options.has_key?(:interruptible) ? options[:interruptible] : true
      execute_component_and_await_completion prompt

      reason = prompt.complete_event.reason

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
