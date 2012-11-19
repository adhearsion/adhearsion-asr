module AdhearsionASR
  module ControllerMethods
    Result = Struct.new(:response, :status, :nlsml, :message) do
      def to_s
        response
      end

      def inspect
        "#<#{self.class} response=#{response.inspect}, status=#{status.inspect}, nlsml=#{nlsml.inspect}, message=#{message}>"
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
          result.response = reason.utterance
          result.status   = :match
          result.nlsml    = reason.nlsml
        when Punchblock::Event::Complete::Error
          raise ListenError, reason.details
        when Punchblock::Event::Complete::Reason
          result.status = reason.name
        else
          raise "Unknown completion reason received: #{reason}"
        end
      end
    end
  end
end
