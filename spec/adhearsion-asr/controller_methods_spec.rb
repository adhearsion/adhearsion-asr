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
        mock call, :write_command => true, :id => call_id
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

      describe "#listen" do
        let(:grxml) {
          RubySpeech::GRXML.draw :root => 'main', :language => 'en-us' do
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

        it "returns the utterance as the response, the instance hash as the interpretation, the nlsml and a status of :match" do
          expect_component_complete_event
          expect_component_execution input_component
          result = subject.listen options: %w{yes no}
          result.response.should be == 'yes'
          result.interpretation.should be == {boo: 'baz'}
          result.status.should be == :match
          result.nlsml.should be == nlsml
        end

        context "when a nomatch occurrs" do
          let(:input_complete_reason) { Punchblock::Component::Input::Complete::NoMatch.new }

          it "should return a response of nil and a status of nomatch" do
            expect_component_complete_event
            expect_component_execution input_component
            result = subject.listen options: %w{yes no}
            result.response.should be nil
            result.interpretation.should be nil
            result.status.should be == :nomatch
          end
        end

        context "when a noinput occurrs" do
          let(:input_complete_reason) { Punchblock::Component::Input::Complete::NoInput.new }

          it "should return a response of nil and a status of noinput" do
            expect_component_complete_event
            expect_component_execution input_component
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
            Punchblock::Component::Output.new ssml: ssml, interrupt_on: :speech
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
