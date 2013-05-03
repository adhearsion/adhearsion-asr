module AdhearsionASR
  class MenuBuilder
    def initialize(options, &block)
      @options = options
      @matchers = []
      @callbacks = {}
      build(&block)
    end

    def match(*args, &block)
      payload = block || args.pop

      @matchers << Matcher.new(payload, args)
    end

    def invalid(&block)
      register_user_supplied_callback :nomatch, &block
    end

    def timeout(&block)
      register_user_supplied_callback :noinput, &block
    end

    def grammar
      @grammar ||= build_grammar
    end

    def process_result(result)
      if result.status == :match
        handle_match result
      else
        execute_hook_for result
      end
    end

    private

    def register_user_supplied_callback(name, &block)
      @callbacks[name] = block
    end

    def execute_hook_for(result)
      callback = @callbacks[result.status]
      return unless callback
      @context.instance_exec result.response, &callback
    end

    def handle_match(result)
      match = @matchers[result.interpretation.to_i]
      match.dispatch @context, result.response
    end

    def build(&block)
      @context = eval "self", block.binding
      instance_eval(&block)
    end

    def build_grammar
      raise ArgumentError, "You must specify one or more matches." if @matchers.count < 1
      matchers = @matchers

      RubySpeech::GRXML.draw mode: :dtmf, root: 'options', tag_format: 'semantics/1.0-literals' do
        rule id: 'options', scope: 'public' do
          item do
            one_of do
              matchers.each_with_index do |matcher, index|
                item do
                  tag { index.to_s }
                  if matcher.keys.count > 1
                    one_of do
                      matcher.keys.each do |key|
                        item { key.to_s }
                      end
                    end
                  else
                    matcher.keys.first.to_s
                  end
                end
              end
            end
          end
        end
      end
    end

    Matcher = Struct.new(:payload, :keys) do
      def dispatch(controller, response)
        if payload.is_a?(Proc)
          controller.instance_exec response, &payload
        else
          controller.invoke payload, extension: response
        end
      end
    end
  end
end
