module AdhearsionASR
  class MenuBuilder
    def initialize(options, &block)
      @options = options
      @matches = []
      @callbacks = {}
      build(&block)
    end

    def match(match, &block)
      @matches << match
    end

    def invalid(&block)
      @callbacks[:nomatch] = block
    end

    def grammar
      @grammar ||= build_grammar
    end

    def process_result(result)
      execute_hook_for result.status, result.response
    end

    private

    def execute_hook_for(status, utterance)
      callback = @callbacks[status]
      return unless callback
      @context.instance_exec utterance, &callback
    end

    def build(&block)
      @context = eval "self", block.binding
      instance_eval(&block)
    end

    def build_grammar
      raise ArgumentError, "You must specify one or more matches." if @matches.count < 1
      matches = @matches

      RubySpeech::GRXML.draw mode: :dtmf, root: 'options' do
        rule id: 'options', scope: 'public' do
          item do
            one_of do
              matches.each { |d| item { d.to_s } }
            end
          end
        end
      end
    end
  end
end
