# encoding: utf-8

require 'spec_helper'

module AdhearsionASR
  describe ControllerMethods do
    describe "mixed in to a CallController" do

      let(:call_id)     { SecureRandom.uuid }
      let(:call)        { Adhearsion::Call.new }
      let(:block)       { nil }
      let(:controller)  { Class.new(Adhearsion::CallController).new call }

      subject { controller }

      before do
        double call, write_command: true, id: call_id
      end

      def expect_component_execution(component, fail = false)
        expectation = controller.should_receive(:execute_component_and_await_completion).ordered.with(component)
        if fail
          expectation.and_raise fail
        else
          expectation.and_return component
        end
        expectation
      end

      def self.temp_config_value(key, value, namespace = Plugin.config)
        before do
          @original_value = namespace[key]
          namespace[key] = value
        end

        after { namespace[key] = @original_value }
      end

      before do
        Adhearsion::Plugin.configure_plugins if Adhearsion::Plugin.respond_to?(:configure_plugins)
        Adhearsion::Plugin.init_plugins
      end

      let(:prompts) { ['http://example.com/nice-to-meet-you.mp3', 'http://example.com/press-some-buttons.mp3'] }

      let :expected_ssml do
        RubySpeech::SSML.draw do
          audio src: 'http://example.com/nice-to-meet-you.mp3'
          audio src: 'http://example.com/press-some-buttons.mp3'
        end
      end

      let :expected_output_options do
        {
          render_document: {value: expected_ssml},
          renderer: nil
        }
      end

      let :expected_input_options do
        {
          mode: :dtmf,
          initial_timeout: 5000,
          inter_digit_timeout: 5000,
          max_silence: 5000,
          min_confidence: 0.5,
          recognizer: nil,
          language: 'en-US',
          grammar: { value: expected_grxml }
        }
      end

      let(:expected_barge_in) { true }

      let :expected_prompt do
        Punchblock::Component::Prompt.new expected_output_options, expected_input_options, barge_in: expected_barge_in
      end

      let(:reason) { Punchblock::Component::Input::Complete::NoMatch.new }

      before { Punchblock::Component::Prompt.any_instance.stub complete_event: double(reason: reason) }

      describe "#ask" do
        let :digit_limit_grammar do
          RubySpeech::GRXML.draw mode: 'dtmf', root: 'digits' do
            rule id: 'digits', scope: 'public' do
              item repeat: '0-5' do
                one_of do
                  0.upto(9) { |d| item { d.to_s } }
                  item { "#" }
                  item { "*" }
                end
              end
            end
          end
        end

        context "without a digit limit, terminator digit or grammar" do
          it "raises ArgumentError" do
            expect { subject.ask prompts }.to raise_error(ArgumentError, "You must specify at least one of limit, terminator or grammar")
          end
        end

        context "with a digit limit" do
          let(:expected_grxml) { digit_limit_grammar }

          it "executes a Prompt component with the correct prompts and grammar" do
            expect_component_execution expected_prompt

            subject.ask prompts, limit: 5
          end

          context "with nil prompts" do
            let(:prompts) { [nil, 'http://example.com/nice-to-meet-you.mp3', 'http://example.com/press-some-buttons.mp3'] }

            it "executes a Prompt component with the correct prompts and grammar" do
              expect_component_execution expected_prompt
              subject.ask prompts, limit: 5
            end
          end

          context "with no prompts" do
            it "executes an Input component with the correct grammar" do
              Punchblock::Component::Input.any_instance.stub complete_event: double(reason: reason)
              expect_component_execution Punchblock::Component::Input.new(expected_input_options)
              subject.ask limit: 5
            end
          end

          context "with only nil prompts" do
            it "executes an Input component with the correct grammar" do
              Punchblock::Component::Input.any_instance.stub complete_event: double(reason: reason)
              expect_component_execution Punchblock::Component::Input.new(expected_input_options)
              subject.ask nil, limit: 5
            end
          end

          context "with a block passed" do
            it "executes but logs a warning about the block validator" do
              expect_component_execution expected_prompt
              call.logger.should_receive(:warn).with(/validator/)
              target = double
              target.should_receive(:foo).never

              subject.ask prompts, limit: 5 do |buffer|
                target.foo
              end
            end
          end
        end

        context "with a terminator" do
          let :expected_grxml do
            RubySpeech::GRXML.draw mode: 'dtmf', root: 'digits' do
              rule id: 'digits', scope: 'public' do
                item repeat: '0-' do
                  one_of do
                    0.upto(9) { |d| item { d.to_s } }
                    item { "#" }
                    item { "*" }
                  end
                end
              end
            end
          end

          before do
            expected_input_options.merge! terminator: '#'
          end

          it "executes a Prompt component with the correct prompts and grammar" do
            expect_component_execution expected_prompt

            subject.ask prompts, terminator: '#'
          end
        end

        context "with a digit limit and a terminator" do
          let :expected_grxml do
            RubySpeech::GRXML.draw mode: 'dtmf', root: 'digits' do
              rule id: 'digits', scope: 'public' do
                item repeat: '0-5' do
                  one_of do
                    0.upto(9) { |d| item { d.to_s } }
                    item { "#" }
                    item { "*" }
                  end
                end
              end
            end
          end

          before do
            expected_input_options.merge! grammar: { value: expected_grxml },
              terminator: '#'
          end

          it "executes a Prompt component with the correct prompts and grammar" do
            expect_component_execution expected_prompt

            subject.ask prompts, limit: 5, terminator: '#'
          end
        end

        context "with an inline GRXML grammar specified" do
          let :expected_grxml do
            RubySpeech::GRXML.draw root: 'main', language: 'en-us', mode: :voice do
              rule id: 'main', scope: 'public' do
                one_of do
                  item { 'yes' }
                  item { 'no' }
                end
              end
            end
          end

          before do
            expected_input_options.merge! grammar: { value: expected_grxml }
          end

          it "executes a Prompt component with the correct prompts and grammar" do
            expect_component_execution expected_prompt

            subject.ask prompts, grammar: expected_grxml
          end

          context "with multiple grammars specified" do
            let :other_expected_grxml do
              RubySpeech::GRXML.draw root: 'main', mode: :dtmf do
                rule id: 'main', scope: 'public' do
                  one_of do
                    item { 1 }
                    item { 2 }
                  end
                end
              end
            end

            before do
              expected_input_options.merge! grammars: [{ value: expected_grxml }, { value: other_expected_grxml }]
            end

            it "executes a Prompt component with the correct prompts and grammar" do
              expect_component_execution expected_prompt

              subject.ask prompts, grammar: [expected_grxml, other_expected_grxml]
            end
          end
        end

        context "with a grammar URL specified" do
          let(:expected_grxml) { digit_limit_grammar }
          let(:grammar_url) { 'http://example.com/cities.grxml' }

          before do
            expected_input_options.merge! grammar: { url: grammar_url }
          end

          it "executes a Prompt component with the correct prompts and grammar" do
            expect_component_execution expected_prompt

            subject.ask prompts, grammar_url: grammar_url
          end

          context "with multiple grammar URLs specified" do
            let(:other_grammar_url) { 'http://example.com/states.grxml' }

            before do
              expected_input_options.merge! grammars: [{ url: grammar_url }, { url: other_grammar_url }]
            end

            it "executes a Prompt component with the correct prompts and grammar" do
              expect_component_execution expected_prompt

              subject.ask prompts, grammar_url: [grammar_url, other_grammar_url]
            end
          end

          context "with grammars specified inline and by URL" do
            before do
              expected_input_options.merge! grammars: [{ value: expected_grxml }, { url: grammar_url }]
            end

            it "executes a Prompt component with the correct prompts and grammar" do
              expect_component_execution expected_prompt

              subject.ask prompts, grammar: expected_grxml, grammar_url: [grammar_url]
            end
          end
        end

        context "with interruptible: false" do
          let(:expected_grxml) { digit_limit_grammar }

          let(:expected_barge_in) { false }

          it "executes a Prompt with barge-in disabled" do
            expect_component_execution expected_prompt

            subject.ask prompts, limit: 5, interruptible: false
          end
        end

        context "with a timeout specified" do
          let(:expected_grxml) { digit_limit_grammar }

          before do
            expected_input_options.merge! initial_timeout: 10000,
              inter_digit_timeout: 10000,
              max_silence: 10000
          end

          it "executes a Prompt with correct timeout (initial, inter-digit & max-silence)" do
            expect_component_execution expected_prompt

            subject.ask prompts, limit: 5, timeout: 10
          end
        end

        context "with a different default timeout" do
          let(:expected_grxml) { digit_limit_grammar }

          before do
            expected_input_options.merge! initial_timeout: 10000,
              inter_digit_timeout: 10000,
              max_silence: 10000
          end

          temp_config_value :timeout, 10

          it "executes a Prompt with correct timeout (initial, inter-digit & max-silence)" do
            expect_component_execution expected_prompt

            subject.ask prompts, limit: 5
          end
        end

        context "with a different default minimum confidence" do
          let(:expected_grxml) { digit_limit_grammar }

          before do
            expected_input_options.merge! min_confidence: 0.8
          end

          temp_config_value :min_confidence, 0.8

          it "executes a Prompt with correct minimum confidence" do
            expect_component_execution expected_prompt

            subject.ask prompts, limit: 5
          end
        end

        context "with a different default recognizer" do
          let(:expected_grxml) { digit_limit_grammar }

          before do
            expected_input_options.merge! recognizer: 'something_else'
          end

          temp_config_value :recognizer, 'something_else'

          it "executes a Prompt with correct recognizer" do
            expect_component_execution expected_prompt

            subject.ask prompts, limit: 5
          end
        end

        context "with a different default input language" do
          let(:expected_grxml) { digit_limit_grammar }

          before do
            expected_input_options.merge! language: 'pt-BR'
          end

          temp_config_value :input_language, 'pt-BR'

          it "executes a Prompt with correct input language" do
            expect_component_execution expected_prompt

            subject.ask prompts, limit: 5
          end
        end

        context "with a different default output renderer" do
          let(:expected_grxml) { digit_limit_grammar }

          before do
            expected_output_options.merge! renderer: 'something_else'
          end

          temp_config_value :default_renderer, 'something_else', Adhearsion.config.platform.media

          it "executes a Prompt with correct renderer" do
            expect_component_execution expected_prompt

            subject.ask prompts, limit: 5
          end
        end

        context "with a different default output voice" do
          let(:expected_grxml) { digit_limit_grammar }

          before do
            expected_output_options.merge! voice: 'something_else'
          end

          temp_config_value :default_voice, 'something_else', Adhearsion.config.platform.media

          it "executes a Prompt with correct voice" do
            expect_component_execution expected_prompt

            subject.ask prompts, limit: 5
          end
        end

        context "with overridden input options" do
          let(:expected_grxml) { digit_limit_grammar }

          before do
            expected_input_options.merge! inter_digit_timeout: 35000
          end

          it "executes a Prompt with correct input options" do
            expect_component_execution expected_prompt

            subject.ask prompts, limit: 5, input_options: {inter_digit_timeout: 35000}
          end
        end

        context "with overridden output options" do
          let(:expected_grxml) { digit_limit_grammar }

          before do
            expected_output_options.merge! max_time: 35000
          end

          it "executes a Prompt with correct output options" do
            expect_component_execution expected_prompt

            subject.ask prompts, limit: 5, output_options: {max_time: 35000}
          end
        end

        context "when the call is dead when trying to execute the prompt" do
          before { call.terminate }

          it "should raise Adhearsion::Call::Hangup" do
            expect { subject.ask prompts, limit: 5 }.to raise_error Adhearsion::Call::Hangup
          end
        end

        context "when a utterance is received" do
          let(:expected_grxml) { digit_limit_grammar }

          before { expect_component_execution expected_prompt }

          let(:result) { subject.ask prompts, limit: 5 }

          context "that is a match" do
            let(:mode) { :dtmf }
            let(:utterance) { '123' }

            let :nlsml do
              utterance = self.utterance
              mode = self.mode
              RubySpeech::NLSML.draw do
                interpretation confidence: 1 do
                  input utterance, mode: mode
                  instance 'Foo'
                end
              end
            end

            let(:reason) { Punchblock::Component::Input::Complete::Match.new nlsml: nlsml }

            it "returns :match status and the utterance" do
              result.status.should be :match
              result.should be_match
              result.mode.should be :dtmf
              result.confidence.should == 1
              result.utterance.should == '123'
              result.interpretation.should == 'Foo'
              result.nlsml.should == nlsml
            end

            context "with speech input" do
              let(:mode) { :speech }
              let(:utterance) { 'Hello world' }

              it "should not alter the utterance" do
                result.utterance.should == 'Hello world'
              end
            end

            context "with a single DTMF digit" do
              context 'with dtmf- prefixes' do
                let(:utterance) { 'dtmf-3' }

                it "removes dtmf- previxes" do
                  result.utterance.should be == '3'
                end
              end

              context 'with "star"' do
                let(:utterance) { "dtmf-star" }

                it "interprets as *" do
                  result.utterance.should be == '*'
                end
              end

              context 'with "*"' do
                let(:utterance) { '*' }

                it "interprets as *" do
                  result.utterance.should be == '*'
                end
              end

              context 'with "pound"' do
                let(:utterance) { 'dtmf-pound' }

                it "interprets pound as #" do
                  result.utterance.should be == '#'
                end
              end

              context 'with "#"' do
                let(:utterance) { '#' }

                it "interprets # as #" do
                  result.utterance.should be == '#'
                end
              end

              context 'without a dtmf- prefix' do
                let(:utterance) { '1' }

                it "correctly interprets the digits" do
                  result.utterance.should be == '1'
                end
              end

              context 'with "star"' do
                let(:utterance) { nil }

                it "is nil when utterance is nil" do
                  result.utterance.should be == nil
                end
              end

              context "when requested via #response" do
                let(:utterance) { 'foo' }

                it "returns the utterance" do
                  result.response.should be == 'foo'
                end
              end
            end

            context "with multiple digits separated by spaces" do
              let(:utterance) { '1 dtmf-5 dtmf-star # 2' }

              it "returns the digits without space separation" do
                result.utterance.should be == '15*#2'
              end
            end
          end

          context "that is a nomatch" do
            let(:reason) { Punchblock::Component::Input::Complete::NoMatch.new }

            it "returns :nomatch status and a nil utterance" do
              result.status.should eql(:nomatch)
              result.should_not be_match
              result.utterance.should be_nil
            end
          end

          context "that is a noinput" do
            let(:reason) { Punchblock::Component::Input::Complete::NoInput.new }

            it "returns :noinput status and a nil utterance" do
              result.status.should eql(:noinput)
              result.should_not be_match
              result.utterance.should be_nil
            end
          end

          context "that is a hangup" do
            let(:reason) { Punchblock::Event::Complete::Hangup.new }

            it "returns :hangup status and a nil utterance" do
              result.status.should eql(:hangup)
              result.should_not be_match
              result.utterance.should be_nil
            end
          end

          context "that is a stop" do
            let(:reason) { Punchblock::Event::Complete::Stop.new }

            it "returns :stop status and a nil utterance" do
              result.status.should eql(:stop)
              result.should_not be_match
              result.utterance.should be_nil
            end
          end

          context "that is an error" do
            let(:reason) { Punchblock::Event::Complete::Error.new details: 'foobar' }

            it "should raise an error with a message of 'foobar" do
              expect { subject.ask prompts, limit: 5 }.to raise_error(AdhearsionASR::Error, /foobar/)
            end
          end
        end
      end

      describe "#menu" do
        context "with no block" do
          it "should raise ArgumentError" do
            expect { subject.menu }.to raise_error(ArgumentError, /specify a block to build the menu/)
          end
        end

        context "with no matches" do
          it "should raise ArgumentError" do
            expect do
              subject.menu "Hello?" do
              end
            end.to raise_error(ArgumentError, /specify one or more matches/)
          end
        end

        context "with several matches specified" do
          let :expected_grxml do
            RubySpeech::GRXML.draw mode: 'dtmf', root: 'options' do
              rule id: 'options', scope: 'public' do
                item do
                  one_of do
                    item do
                      tag { '0' }
                      '1'
                    end
                  end
                end
              end
            end
          end

          let(:foo) { :bar }

          it "makes the block context available" do
            expect_component_execution expected_prompt
            doo = nil
            subject.menu prompts do
              doo = foo
              match(1) { do_nothing }
            end
            doo.should == :bar
          end

          context "with nil prompts" do
            let(:prompts) { [nil, 'http://example.com/nice-to-meet-you.mp3', 'http://example.com/press-some-buttons.mp3'] }

            it "executes a Prompt component with the correct prompts and grammar" do
              expect_component_execution expected_prompt
              subject.menu prompts do
                match(1) {}
              end
            end
          end

          context "with no prompts" do
            it "executes an Input component with the correct grammar" do
              Punchblock::Component::Input.any_instance.stub complete_event: double(reason: reason)
              expect_component_execution Punchblock::Component::Input.new(expected_input_options)
              subject.menu do
                match(1) {}
              end
            end
          end

          context "with only nil prompts" do
            it "executes an Input component with the correct grammar" do
              Punchblock::Component::Input.any_instance.stub complete_event: double(reason: reason)
              expect_component_execution Punchblock::Component::Input.new(expected_input_options)
              subject.menu nil do
                match(1) {}
              end
            end
          end

          context "with interruptible: false" do
            let(:expected_barge_in) { false }

            it "executes a Prompt with barge-in disabled" do
              expect_component_execution expected_prompt

              subject.menu prompts, interruptible: false do
                match(1) {}
              end
            end
          end

          context "with a timeout specified" do
            before do
              expected_input_options.merge! initial_timeout: 10000,
                inter_digit_timeout: 10000,
                max_silence: 10000
            end

            it "executes a Prompt with correct timeout (initial, inter-digit & max-silence)" do
              expect_component_execution expected_prompt

              subject.menu prompts, timeout: 10 do
                match(1) {}
              end
            end
          end

          context "with a different default timeout" do
            before do
              expected_input_options.merge! initial_timeout: 10000,
                inter_digit_timeout: 10000,
                max_silence: 10000
            end

            temp_config_value :timeout, 10

            it "executes a Prompt with correct timeout (initial, inter-digit & max-silence)" do
              expect_component_execution expected_prompt

              subject.menu prompts do
                match(1) {}
              end
            end
          end

          context "with a different default minimum confidence" do
            before do
              expected_input_options.merge! min_confidence: 0.8
            end

            temp_config_value :min_confidence, 0.8

            it "executes a Prompt with correct minimum confidence" do
              expect_component_execution expected_prompt

              subject.menu prompts do
                match(1) {}
              end
            end
          end

          context "with a different default recognizer" do
            before do
              expected_input_options.merge! recognizer: 'something_else'
            end

            temp_config_value :recognizer, 'something_else'

            it "executes a Prompt with correct recognizer" do
              expect_component_execution expected_prompt

              subject.menu prompts do
                match(1) {}
              end
            end
          end

          context "with a different default input language" do
            before do
              expected_input_options.merge! language: 'pt-BR'
            end

            temp_config_value :input_language, 'pt-BR'

            it "executes a Prompt with correct input language" do
              expect_component_execution expected_prompt

              subject.menu prompts do
                match(1) {}
              end
            end
          end

          context "with a different default output renderer" do
            before do
              expected_output_options.merge! renderer: 'something_else'
            end

            temp_config_value :default_renderer, 'something_else', Adhearsion.config.platform.media

            it "executes a Prompt with correct renderer" do
              expect_component_execution expected_prompt

              subject.menu prompts do
                match(1) {}
              end
            end
          end

          context "with a different default output voice" do
            before do
              expected_output_options.merge! voice: 'something_else'
            end

            temp_config_value :default_voice, 'something_else', Adhearsion.config.platform.media

            it "executes a Prompt with correct voice" do
              expect_component_execution expected_prompt

              subject.menu prompts do
                match(1) {}
              end
            end
          end

          context "with overridden input options" do
            before do
              expected_input_options.merge! inter_digit_timeout: 35000
            end

            it "executes a Prompt with correct input options" do
              expect_component_execution expected_prompt

              subject.menu prompts, input_options: {inter_digit_timeout: 35000} do
                match(1) {}
              end
            end
          end

          context "with overridden output options" do
            before do
              expected_output_options.merge! max_time: 35000
            end

            it "executes a Prompt with correct output options" do
              expect_component_execution expected_prompt

              subject.menu prompts, output_options: {max_time: 35000} do
                match(1) {}
              end
            end
          end

          context "when using ASR mode" do
            before do
              expected_input_options.merge! mode: :voice
            end

            let :expected_grxml do
              RubySpeech::GRXML.draw mode: 'voice', root: 'options', tag_format: 'semantics/1.0-literals' do
                rule id: 'options', scope: 'public' do
                  item do
                    one_of do
                      item do
                        tag { '0' }
                        'Hello world'
                      end
                    end
                  end
                end
              end
            end

            it "executes a Prompt with correct input mode, and the correct grammar mode" do
              expect_component_execution expected_prompt

              subject.menu prompts, mode: :voice do
                match("Hello world") {}
              end
            end
          end

          context "when the call is dead when trying to execute the prompt" do
            before { call.terminate }

            it "should raise Adhearsion::Call::Hangup" do
              expect do
                subject.menu prompts do
                  match(1) {}
                end
              end.to raise_error Adhearsion::Call::Hangup
            end
          end

          context "when input completes with an error" do
            let(:reason) { Punchblock::Event::Complete::Error.new details: 'foobar' }

            it "should raise an error with a message of 'foobar'" do
              expect_component_execution expected_prompt

              expect do
                subject.menu prompts do
                  match(1) {}
                end
              end.to raise_error(AdhearsionASR::Error, /foobar/)
            end
          end

          context "when input doesn't match any of the specified matches" do
            it "runs the invalid and failure handlers" do
              expect_component_execution expected_prompt
              should_receive(:do_something_on_invalid).once.ordered
              should_receive(:do_something_on_failure).once.ordered

              subject.menu prompts do
                match(1) {}

                invalid { do_something_on_invalid }
                failure { do_something_on_failure }
              end
            end

            context "when allowed multiple tries" do
              let :nlsml do
                RubySpeech::NLSML.draw do
                  interpretation confidence: 1 do
                    input '1', mode: :dtmf
                    instance '0'
                  end
                end
              end

              let(:reason2) { Punchblock::Component::Input::Complete::Match.new nlsml: nlsml }

              it "executes the prompt repeatedly until it gets a match" do
                some_controller_class = Class.new Adhearsion::CallController

                expect_component_execution(expected_prompt).twice
                should_receive(:do_something_on_invalid).once.ordered
                should_receive(:invoke).once.with(some_controller_class, extension: '1').ordered
                should_receive(:do_something_on_failure).never

                invocation_count = 0
                Punchblock::Component::Prompt.any_instance.stub(:complete_event) do
                  invocation_count += 1
                  case invocation_count
                  when 1 then double(reason: reason)
                  when 2 then double(reason: reason2)
                  else raise('Too many attempts')
                  end
                end

                subject.menu prompts, tries: 3 do
                  match 1, some_controller_class

                  invalid { do_something_on_invalid }
                  failure { do_something_on_failure }
                end
              end
            end
          end

          context "when we don't get any input" do
            let(:reason) { Punchblock::Component::Input::Complete::NoInput.new }

            it "runs the timeout and failure handlers" do
              expect_component_execution expected_prompt
              should_receive(:do_something_on_timeout).once.ordered
              should_receive(:do_something_on_failure).once.ordered

              subject.menu prompts do
                match(1) {}

                timeout { do_something_on_timeout }
                failure { do_something_on_failure }
              end
            end

            context "when allowed multiple tries" do
              let :nlsml do
                RubySpeech::NLSML.draw do
                  interpretation confidence: 1 do
                    input '1', mode: :dtmf
                    instance '0'
                  end
                end
              end

              let(:reason2) { Punchblock::Component::Input::Complete::Match.new nlsml: nlsml }

              it "executes the prompt repeatedly until it gets a match" do
                some_controller_class = Class.new Adhearsion::CallController

                expect_component_execution(expected_prompt).twice
                should_receive(:do_something_on_timeout).once.ordered
                should_receive(:invoke).once.with(some_controller_class, extension: '1').ordered
                should_receive(:do_something_on_failure).never

                invocation_count = 0
                Punchblock::Component::Prompt.any_instance.stub(:complete_event) do
                  invocation_count += 1
                  case invocation_count
                  when 1 then double(reason: reason)
                  when 2 then double(reason: reason2)
                  else raise('Too many attempts')
                  end
                end

                subject.menu prompts, tries: 3 do
                  match 1, some_controller_class

                  timeout { do_something_on_timeout }
                  failure { do_something_on_failure }
                end
              end
            end
          end

          context "when the input unambiguously matches a specified match" do
            let :expected_grxml do
              RubySpeech::GRXML.draw mode: 'dtmf', root: 'options', tag_format: 'semantics/1.0-literals' do
                rule id: 'options', scope: 'public' do
                  item do
                    one_of do
                      item do
                        tag { '0' }
                        '2'
                      end
                      item do
                        tag { '1' }
                        '1'
                      end
                      item do
                        tag { '2' }
                        '3'
                      end
                    end
                  end
                end
              end
            end

            let :nlsml do
              RubySpeech::NLSML.draw do
                interpretation confidence: 1 do
                  input '3', mode: :dtmf
                  instance '2'
                end
              end
            end

            let(:reason) { Punchblock::Component::Input::Complete::Match.new nlsml: nlsml }

            context "which specifies a controller class" do
              it "invokes the specfied controller, with the matched input as the :extension key in its metadata" do
                some_controller_class = Class.new Adhearsion::CallController

                expect_component_execution expected_prompt
                should_receive(:invoke).once.with(some_controller_class, extension: '3')

                subject.menu prompts do
                  match(2) {}
                  match(1) {}
                  match 3, some_controller_class
                end
              end
            end

            context "which specifies a block to be run" do
              it "invokes the block, passing in the input that matched" do
                expect_component_execution expected_prompt
                should_receive(:do_something_on_match).once.with('3')

                subject.menu prompts do
                  match(2) {}
                  match(1) {}
                  match(3) { |v| do_something_on_match v }
                end
              end
            end

            context "when the match was a set of options" do
              let :expected_grxml do
                RubySpeech::GRXML.draw mode: 'dtmf', root: 'options', tag_format: 'semantics/1.0-literals' do
                  rule id: 'options', scope: 'public' do
                    item do
                      one_of do
                        item do
                          tag { '0' }
                          '0'
                        end
                        item do
                          tag { '1' }
                          '1'
                        end
                        item do
                          tag { '2' }
                          one_of do
                            item { '2' }
                            item { '3' }
                          end
                        end
                      end
                    end
                  end
                end
              end

              it "invokes the match payload" do
                expect_component_execution expected_prompt
                should_receive(:do_something_on_match).once.with('3')

                subject.menu prompts do
                  match(0) {}
                  match(1) {}
                  match(2,3) { |v| do_something_on_match v }
                end
              end
            end

            context "when the match was a range" do
              let :expected_grxml do
                RubySpeech::GRXML.draw mode: 'dtmf', root: 'options', tag_format: 'semantics/1.0-literals' do
                  rule id: 'options', scope: 'public' do
                    item do
                      one_of do
                        item do
                          tag { '0' }
                          '0'
                        end
                        item do
                          tag { '1' }
                          '1'
                        end
                        item do
                          tag { '2' }
                          one_of do
                            item { '2' }
                            item { '3' }
                          end
                        end
                      end
                    end
                  end
                end
              end

              it "invokes the match payload" do
                expect_component_execution expected_prompt
                should_receive(:do_something_on_match).once.with('3')

                subject.menu prompts do
                  match(0) {}
                  match(1) {}
                  match(2..3) { |v| do_something_on_match v }
                end
              end
            end

            context "when the match was an array of options" do
              let :expected_grxml do
                RubySpeech::GRXML.draw mode: 'dtmf', root: 'options', tag_format: 'semantics/1.0-literals' do
                  rule id: 'options', scope: 'public' do
                    item do
                      one_of do
                        item do
                          tag { '0' }
                          '0'
                        end
                        item do
                          tag { '1' }
                          '1'
                        end
                        item do
                          tag { '2' }
                          one_of do
                            item { '2' }
                            item { '3' }
                          end
                        end
                      end
                    end
                  end
                end
              end

              it "invokes the match payload" do
                expect_component_execution expected_prompt
                should_receive(:do_something_on_match).once.with('3')

                subject.menu prompts do
                  match(0) {}
                  match(1) {}
                  match([2,3]) { |v| do_something_on_match v }
                end
              end
            end
          end

          context "when the input abmiguously matches multiple specified matches" do
            let :expected_grxml do
              RubySpeech::GRXML.draw mode: 'dtmf', root: 'options', tag_format: 'semantics/1.0-literals' do
                rule id: 'options', scope: 'public' do
                  item do
                    one_of do
                      item do
                        tag { '0' }
                        '1'
                      end
                      item do
                        tag { '1' }
                        '1'
                      end
                    end
                  end
                end
              end
            end

            let :nlsml do
              RubySpeech::NLSML.draw do
                interpretation confidence: 1 do
                  input '1', mode: :dtmf
                  instance '0'
                  instance '1'
                end
              end
            end

            let(:reason) { Punchblock::Component::Input::Complete::Match.new nlsml: nlsml }

            it "executes the first successful match" do
              expect_component_execution expected_prompt
              should_receive(:do_something_on_match).once.with('1')
              should_receive(:do_otherthing_on_match).never

              subject.menu prompts do
                match(1) { |v| do_something_on_match v }
                match(1) { |v| do_otherthing_on_match v }
              end
            end
          end
        end
      end
    end
  end
end
