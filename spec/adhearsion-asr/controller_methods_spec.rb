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

      before do
        controller.extend AdhearsionASR::ControllerMethods
      end

      describe "#ask" do
        let(:prompts) { ['http://example.com/nice-to-meet-you.mp3', 'http://example.com/press-some-buttons.mp3'] }

        let :expected_ssml do
          RubySpeech::SSML.draw do
            audio src: 'http://example.com/nice-to-meet-you.mp3'
            audio src: 'http://example.com/press-some-buttons.mp3'
          end
        end

        let :expected_output_options do
          {render_document: {value: expected_ssml}}
        end

        let :expected_input_options do
          {
            mode: :dtmf,
            initial_timeout: 5000,
            inter_digit_timeout: 5000,
            grammar: { value: expected_grxml }
          }
        end

        let(:expected_barge_in) { true }

        let :expected_prompt do
          Punchblock::Component::Prompt.new expected_output_options, expected_input_options, barge_in: expected_barge_in
        end

        let(:reason) { Punchblock::Component::Input::Complete::NoMatch.new }

        before { Punchblock::Component::Prompt.any_instance.stub complete_event: mock(reason: reason) }

        context "without a digit limit, terminator digit or grammar" do
          it "raises ArgumentError" do
            expect { subject.ask prompts }.to raise_error(ArgumentError, "You must specify at least one of limit, terminator or grammar")
          end
        end

        context "with a digit limit" do
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

          let :expected_input_options do
            {
              mode: :dtmf,
              initial_timeout: 5000,
              inter_digit_timeout: 5000,
              grammar: { value: expected_grxml },
              terminator: '#'
            }
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

          let :expected_input_options do
            {
              mode: :dtmf,
              initial_timeout: 5000,
              inter_digit_timeout: 5000,
              grammar: { value: expected_grxml },
              terminator: '#'
            }
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

          let :expected_input_options do
            {
              mode: :speech,
              initial_timeout: 5000,
              inter_digit_timeout: 5000,
              grammar: { value: expected_grxml }
            }
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

            let :expected_input_options do
              {
                mode: :any,
                initial_timeout: 5000,
                inter_digit_timeout: 5000,
                grammars: [{ value: expected_grxml }, { value: other_expected_grxml }]
              }
            end

            it "executes a Prompt component with the correct prompts and grammar" do
              expect_component_execution expected_prompt

              subject.ask prompts, grammar: [expected_grxml, other_expected_grxml]
            end
          end
        end

        context "with :interruptible: false" do
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

          let(:expected_barge_in) { false }

          it "executes a Prompt with barge-in disabled" do
            expect_component_execution expected_prompt

            subject.ask prompts, limit: 5, interruptible: false
          end
        end

        context "with a timeout specified" do
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

          let :expected_input_options do
            {
              mode: :dtmf,
              initial_timeout: 10000,
              inter_digit_timeout: 10000,
              grammar: { value: expected_grxml }
            }
          end

          it "executes a Prompt with correct timeout (initial & inter-digit)" do
            expect_component_execution expected_prompt

            subject.ask prompts, limit: 5, timeout: 10
          end
        end

        context "when a response is received" do
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

      describe "#listen" do
        before { pending }
        let(:grxml) {
          RubySpeech::GRXML.draw root: 'main', language: 'en-us' do
            rule id: 'main', scope: 'public' do
              one_of do
                item { 'yes' }
                item { 'no' }
              end
            end
          end
        }

        let(:input_component) {
          Punchblock::Component::Input.new grammar: { value: grxml }, min_confidence: 0.5, recognizer: 'en-us'
        }

        let(:nlsml) do
          RubySpeech::NLSML.draw do
            interpretation confidence: 1 do
              input "yes", mode: :speech

              instance do
                boo 'baz'
              end
            end
          end
        end

        let(:input_complete_reason) { Punchblock::Component::Input::Complete::Match.new nlsml: nlsml }
        let(:input_complete_event)  { Punchblock::Event::Complete.new reason: input_complete_reason }

        def expect_component_complete_event
          Punchblock::Component::Input.any_instance.should_receive(:complete_event).at_least(:once).and_return(input_complete_event)
        end

        before do
          @mock_logger = mock("mock logger")
        end

        it "sends the correct input component" do
          expect_component_complete_event
          expect_component_execution input_component
          subject.listen options: %w{yes no}
        end

        it "can execute a user-specified grammar" do
          expect_component_complete_event
          expect_component_execution input_component
          subject.listen grammar: grxml
        end

        it "can execute a grammar by url" do
          expect_component_complete_event
          url = "http://foo.com/bar.grxml"
          input_component.grammar = {url: url}
          expect_component_execution input_component
          subject.listen grammar_url: url
        end

        it "should default the recognition language to 'en-us'" do
          expect_component_complete_event
          controller.should_receive(:execute_component_and_await_completion).once.ordered do |component|
            grammar = component.grammar.value
            grammar['lang'].should == 'en-us'
          end
          subject.listen options: %w{yes no}
        end

        it "allows specifying a recognition language" do
          expect_component_complete_event
          controller.should_receive(:execute_component_and_await_completion).once.ordered do |component|
            grammar = component.grammar.value
            grammar['lang'].should == 'en-gb'
          end
          subject.listen options: %w{yes no}, language: 'en-gb'
        end

        it "allows specifying a recognizer" do
          expect_component_complete_event
          input_component.recognizer = 'pt-BR'
          expect_component_execution input_component
          subject.listen options: %w{yes no}, recognizer: 'pt-BR'
        end

        it "allows specifying a min confidence" do
          expect_component_complete_event
          input_component.min_confidence = 0.1
          expect_component_execution input_component
          subject.listen options: %w{yes no}, min_confidence: 0.1
        end

        it "raises ArgumentError when not provided options, a grammar or a grammar URL" do
          expect { subject.listen }.to raise_error(ArgumentError, "You must provide a grammar, a grammar URL or a set of options")
        end

        it "returns the utterance as the response, the confidence as a number between 0 and 1, the instance hash as the interpretation, the nlsml and a status of :match" do
          expect_component_complete_event
          expect_component_execution input_component
          result = subject.listen options: %w{yes no}
          result.response.should be == 'yes'
          result.confidence.should be == 1.0
          result.interpretation.should be == {boo: 'baz'}
          result.status.should be == :match
          result.nlsml.should be == nlsml
        end

        it "should log the results to DEBUG" do
          expect_component_complete_event
          expect_component_execution input_component
          subject.should_receive(:logger).and_return @mock_logger
          @mock_logger.should_receive(:debug).with "Received input 'yes' with confidence 1.0"
          subject.listen options: %w{yes no}
        end

        context "when a nomatch occurrs" do
          let(:input_complete_reason) { Punchblock::Component::Input::Complete::NoMatch.new }

          it "should return a response of nil, a status of nomatch, and log the nomatch to DEBUG" do
            expect_component_complete_event
            expect_component_execution input_component
            subject.should_receive(:logger).and_return @mock_logger
            @mock_logger.should_receive(:debug).with "Listen has completed with status 'nomatch'"
            result = subject.listen options: %w{yes no}
            result.response.should be nil
            result.interpretation.should be nil
            result.status.should be == :nomatch
          end
        end

        context "when a noinput occurrs" do
          let(:input_complete_reason) { Punchblock::Component::Input::Complete::NoInput.new }

          it "should return a response of nil, a status of noinput, and log the noinput to DEBUG" do
            expect_component_complete_event
            expect_component_execution input_component
            subject.should_receive(:logger).and_return @mock_logger
            @mock_logger.should_receive(:debug).with "Listen has completed with status 'noinput'"
            result = subject.listen options: %w{yes no}
            result.response.should be nil
            result.interpretation.should be nil
            result.status.should be == :noinput
          end
        end

        context "when an error occurrs" do
          let(:input_complete_reason) { Punchblock::Event::Complete::Error.new details: 'foobar' }

          it "should raise an error with a message of 'foobar" do
            expect_component_complete_event
            expect_component_execution input_component
            expect { subject.listen options: %w{yes no} }.to raise_error(AdhearsionASR::ListenError, /foobar/)
          end
        end

        context "when interruptible output is provided" do
          let(:prompt) { "Press 3 or 5 to make something happen." }

          let(:ssml) do
            RubySpeech::SSML.draw do
              string "Press 3 or 5 to make something happen."
            end
          end

          let(:output_component) do
            Punchblock::Component::Output.new ssml: ssml
          end

          let(:output_complete_event) do
            reason = Punchblock::Component::Output::Complete::Success.new
            Punchblock::Event::Complete.new reason: reason
          end

          def expect_output_completion
            Punchblock::Component::Output.any_instance.should_receive(:complete_event).at_least(:once).and_return(output_complete_event)
          end

          it "plays the correct output" do
            expect_component_complete_event
            expect_output_completion
            expect_message_waiting_for_response input_component
            expect_message_waiting_for_response output_component
            subject.listen prompt: prompt, options: %w{yes no}
          end

          it "should terminate the output when the input completes" do
            latch = CountDownLatch.new 1

            expect_message_waiting_for_response input_component
            input_component.request!
            input_component.execute!
            Punchblock::Component::Input.should_receive(:new).and_return(input_component)
            expect_message_waiting_for_response output_component
            output_component.request!
            output_component.execute!
            Punchblock::Component::Output.should_receive(:new).and_return(output_component)

            thread = Thread.new do
              result = subject.listen prompt: prompt, options: %w{yes no}
              latch.countdown!
              result
            end
            latch.wait(1).should be_false

            output_component.should_receive(:stop!).once do
              output_component.add_event output_complete_event
            end

            input_component.add_event input_complete_event
            input_component.trigger_event_handler input_complete_event

            latch.wait(1).should be_true

            thread.join.should_not be_nil
          end

          context "with a collection of prompts" do
            let(:prompts) { ["/srv/foo.mp3", "Press 3 or 5 to make something happen."] }

            let(:ssml) do
              RubySpeech::SSML.draw do
                audio src: '/srv/foo.mp3'
                string "Press 3 or 5 to make something happen."
              end
            end

            it "plays all prompts concatenated" do
              expect_component_complete_event
              expect_output_completion
              expect_message_waiting_for_response input_component
              expect_message_waiting_for_response output_component
              original_options = {prompt: prompts, options: %w{yes no}}
              options = original_options.dup
              subject.listen options
              options.should == original_options
            end
          end
        end
      end
    end
  end
end
