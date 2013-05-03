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
        mock call, write_command: true, id: call_id
      end

      def expect_message_waiting_for_response(message, fail = false)
        expectation = controller.should_receive(:write_and_await_response).once.with message
        if fail
          expectation.and_raise fail
        else
          expectation.and_return message
        end
      end

      def expect_message_of_type_waiting_for_response(message)
        controller.should_receive(:write_and_await_response).once.with(message.class).and_return message
      end

      def expect_component_execution(component, fail = false)
        expectation = controller.should_receive(:execute_component_and_await_completion).once.ordered.with(component)
        if fail
          expectation.and_raise fail
        else
          expectation.and_return component
        end
      end

      def self.temp_config_value(key, value)
        before do
          @original_value = Plugin.config[key]
          Plugin.config[key] = value
        end

        after { Plugin.config[key] = @original_value }
      end

      before do
        controller.extend AdhearsionASR::ControllerMethods
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

      before { Punchblock::Component::Prompt.any_instance.stub complete_event: mock(reason: reason) }

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

          temp_config_value :renderer, 'something_else'

          it "executes a Prompt with correct renderer" do
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

        context "when a response is received" do
          let(:expected_grxml) { digit_limit_grammar }

          context "that is a match" do
            let :nlsml do
              RubySpeech::NLSML.draw do
                interpretation confidence: 1 do
                  input '123', mode: :dtmf
                  instance 'Foo'
                end
              end
            end

            let(:reason) { Punchblock::Component::Input::Complete::Match.new nlsml: nlsml }

            it "returns :match status and the response" do
              expect_component_execution expected_prompt

              result = subject.ask prompts, limit: 5
              result.status.should be :match
              result.confidence.should == 1
              result.response.should == '123'
              result.interpretation.should == 'Foo'
              result.nlsml.should == nlsml
            end
          end

          context "that is a nomatch" do
            let(:reason) { Punchblock::Component::Input::Complete::NoMatch.new }

            it "returns :nomatch status and a nil response" do
              expect_component_execution expected_prompt

              result = subject.ask prompts, limit: 5
              result.status.should be :nomatch
              result.response.should be_nil
            end
          end

          context "that is a noinput" do
            let(:reason) { Punchblock::Component::Input::Complete::NoInput.new }

            it "returns :noinput status and a nil response" do
              expect_component_execution expected_prompt

              result = subject.ask prompts, limit: 5
              result.status.should be :noinput
              result.response.should be_nil
            end
          end

          context "that is an error" do
            let(:reason) { Punchblock::Event::Complete::Error.new details: 'foobar' }

            it "should raise an error with a message of 'foobar" do
              expect_component_execution expected_prompt

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
              subject.menu do
              end
            end.to raise_error(ArgumentError, /specify one or more matches/)
          end
        end

        context "tries"

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

            temp_config_value :renderer, 'something_else'

            it "executes a Prompt with correct renderer" do
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
            it "runs the invalid handler" do
              expect_component_execution expected_prompt
              should_receive :do_something_on_invalid

              subject.menu prompts do
                match(1) {}

                invalid { do_something_on_invalid }
              end
            end
          end

          context "when we don't get any input" do
            let(:reason) { Punchblock::Component::Input::Complete::NoInput.new }

            it "runs the timeout handler" do
              expect_component_execution expected_prompt
              should_receive :do_something_on_timeout

              subject.menu prompts do
                match(1) {}

                timeout { do_something_on_timeout }
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
        end
      end
    end
  end
end
