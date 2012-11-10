module AdhearsionASR
  module ControllerMethods
    Result = Struct.new(:response, :status, :nlsml) do
      def to_s
        response
      end

      def inspect
        "#<#{self.class} response=#{response.inspect}, status=#{status.inspect}, nlsml=#{nlsml.inspect}>"
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
    #
    #
    def listen(opts = {})
      raise ArgumentError, "You must provide a grammar, a grammar URL or a set of options" unless opts[:grammar] || opts[:grammar_url] || opts[:options].respond_to?(:each)
      grammar_opts = if opts[:grammar_url]
        { url: opts[:grammar_url] }
      else
        grammar = opts[:grammar]
        grammar ||= RubySpeech::GRXML.draw root: 'main' do
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
      input_options = opts.merge(grammar: grammar_opts)
      prompts = Array(opts.delete :prompt)
      [:prompt, :options, :grammar_url].each { |o| input_options.delete o }

      input_component = Punchblock::Component::Input.new input_options
      execute_component_and_await_completion input_component do
        player.output Adhearsion::CallController::Output::Formatter.ssml_for_collection(prompts) if prompts.any?
      end

      reason = input_component.complete_event.reason

      Result.new.tap do |result|
        case reason
        when proc { |r| r.respond_to? :nlsml }
          result.response = reason.utterance
          result.status   = :match
          result.nlsml    = reason.nlsml
        else
          result.status = :nomatch
        end
      end
    end
  end
end
