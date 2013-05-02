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
    #
    # @return [Result] a result object from which the details of the response may be established
    #
    # @see Output#play
    #
    def ask(*args, &block)
      options = args.last.kind_of?(Hash) ? args.pop : {}
      prompts = args.flatten

      options[:grammar] || options[:limit] || options[:terminator] || raise(ArgumentError, "You must specify at least one of limit, terminator or grammar")

      grammars = if options[:grammar]
        [options[:grammar]].flatten.compact.map { |val| {value: val} }
      else
        grammar = RubySpeech::GRXML.draw(mode: :dtmf, root: 'digits') do
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
        [{value: grammar}]
      end
      output_options = {
        render_document: {value: output_formatter.ssml_for_collection(prompts)}
      }
      grammar_modes = grammars.map { |g| g[:value].mode == :voice ? :speech : g[:value].mode }.uniq
      input_mode = grammar_modes.count > 1 ? :any : grammar_modes.first
      input_options = {
        mode: input_mode,
        initial_timeout: (options[:timeout] || Plugin.config.timeout) * 1000,
        inter_digit_timeout: (options[:timeout] || Plugin.config.timeout) * 1000,
        max_silence: (options[:timeout] || Plugin.config.timeout) * 1000,
        grammars: grammars,
        terminator: options[:terminator]
      }

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

    #
    # Listens for speech input from the caller and matches against a collection of possible responses
    #
    # @param [Hash] :opts
    # @option :opts [Object] :prompt a prompt to play while listening for input. Accepts anything that `Adhearsion::CallController#play does`.
    # @option :opts [Enumerable<String>] :options a collection of possible options
    # @option :opts [RubySpeech::GRXML::Grammar, String] :grammar a GRXML grammar
    # @option :opts [String] :grammar_url a URL to a grammar
    # @option :opts [Integer, optional] :max_silence the amount of time in milliseconds that an input command will wait until considered that a silence becomes a NO-MATCH
    # @option :opts [Float, optional] :min_confidence with which to consider a response acceptable
    # @option :opts [Symbol, optional] :mode by which to accept input. Can be :speech, :dtmf or :any
    # @option :opts [String, optional] :recognizer to use for speech recognition
    # @option :opts [String, optional] :terminator by which to signal the end of input
    # @option :opts [Float, optional] :sensitivity Indicates how sensitive the interpreter should be to loud versus quiet input. Higher values represent greater sensitivity.
    # @option :opts [Integer, optional] :initial_timeout Indicates the amount of time preceding input which may expire before a timeout is triggered.
    # @option :opts [Integer, optional] :inter_digit_timeout Indicates (in the case of DTMF input) the amount of time between input digits which may expire before a timeout is triggered.
    # @option :opts [Integer, optional] :timeout Times out the grammar (and terminates output) if no response after this value in seconds
    #
    def listen(opts = {})
      opts = opts.dup
      raise ArgumentError, "You must provide a grammar, a grammar URL or a set of options" unless opts[:grammar] || opts[:grammar_url] || opts[:options].respond_to?(:each)
      grammar_opts = if opts[:grammar_url]
        { url: opts[:grammar_url] }
      else
        language = opts.delete(:language) || AdhearsionASR::Plugin.config[:language]
        grammar = opts.delete(:grammar)
        grammar ||= RubySpeech::GRXML.draw root: 'main', language: language do
          rule id: 'main', scope: 'public' do
            one_of do
              opts[:options].each do |option|
                item { option }
              end
            end
          end
        end
        { value: grammar }
      end
      input_options = {grammar: grammar_opts, min_confidence: AdhearsionASR::Plugin.config[:min_confidence], recognizer: AdhearsionASR::Plugin.config[:recognizer]}.merge(opts)
      prompts = Array(opts.delete :prompt)
      timeout = opts.has_key?(:timeout) ? opts.delete(:timeout) : AdhearsionASR::Plugin.config[:timeout]
      [:prompt, :options, :grammar_url, :timeout].each { |o| input_options.delete o }

      input_component = Punchblock::Component::Input.new input_options

      if prompts.any?
        output = player.output Adhearsion::CallController::Output::Formatter.ssml_for_collection(prompts) do |output_component|
          input_component.register_event_handler Punchblock::Event::Complete do |event|
            unless output_component.complete?
              output_component.stop!
            end
          end
          write_and_await_response input_component
        end
        output.complete_event
      else
        execute_component_and_await_completion input_component
      end

      if timeout
        call.after(timeout) do
          logger.debug "Timeout triggered, halting input component"
          input_component.stop! unless input_component.complete?
        end
      end

      reason = input_component.complete_event.reason

      Result.new.tap do |result|
        case reason
        when proc { |r| r.respond_to? :nlsml }
          result.response       = reason.utterance
          result.confidence     = reason.confidence
          result.interpretation = reason.interpretation
          result.status         = :match
          result.nlsml          = reason.nlsml
          logger.debug "Received input '#{result.response}' with confidence #{result.confidence}"
        when Punchblock::Event::Complete::Error
          raise ListenError, reason.details
        when Punchblock::Event::Complete::Reason
          result.status = reason.name
          logger.debug "Listen has completed with status '#{result.status}'"
        else
          raise "Unknown completion reason received: #{reason}"
        end
      end
    end
  end
end
