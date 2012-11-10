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
          RubySpeech::GRXML.draw :root => 'main' do
            rule id: 'main', scope: 'public' do
              one_of do
                item { 'yes' }
                item { 'no' }
              end
            end
          end
        }

        let(:input_component) {
          Punchblock::Component::Input.new grammar: { value: grxml }, min_confidence: 0.5
        }

        let(:nlsml) do
          RubySpeech::NLSML.draw do
            interpretation confidence: 1 do
              input "yes", mode: :speech
            end
          end
        end

        def expect_component_complete_event(reason = nil)
          reason ||= Punchblock::Component::Input::Complete::Match.new :nlsml => nlsml
          complete_event = Punchblock::Event::Complete.new :reason => reason
          Punchblock::Component::Input.any_instance.should_receive(:complete_event).at_least(:once).and_return(complete_event)
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
          input_component = Punchblock::Component::Input.new grammar: { url: url }, min_confidence: 0.5
          expect_component_execution input_component
          subject.listen grammar_url: url
        end

        it "raises ArgumentError when not provided options, a grammar or a grammar URL" do
          expect { subject.listen }.to raise_error(ArgumentError, "You must provide a grammar, a grammar URL or a set of options")
        end

        it "returns the interpretation as the response, the nlsml and a status of :match" do
          expect_component_complete_event
          expect_component_execution input_component
          result = subject.listen options: %w{yes no}
          result.response.should be == 'yes'
          result.status.should be == :match
          result.nlsml.should be == nlsml
        end

        context "with a nil timeout" do
          it "does not set a timeout on the component" do
            pending
            expect_component_complete_event
            expect_component_execution input_component
            subject.wait_for_digit timeout
          end
        end

        context "when a nomatch occurrs" do
          before do
            expect_component_complete_event Punchblock::Component::Input::Complete::NoMatch.new
          end

          it "should return a response of nil and a status of nomatch" do
            expect_component_execution input_component
            result = subject.listen options: %w{yes no}
            result.response.should be nil
            result.status.should be == :nomatch
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

          def expect_output_completion
            reason ||= Punchblock::Component::Output::Complete::Success.new
            complete_event = Punchblock::Event::Complete.new :reason => reason
            Punchblock::Component::Output.any_instance.should_receive(:complete_event).at_least(:once).and_return(complete_event)
          end

          it "plays the correct output" do
            expect_component_complete_event
            expect_output_completion
            expect_message_waiting_for_response input_component
            expect_message_waiting_for_response output_component
            subject.listen prompt: prompt, options: %w{yes no}
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
              subject.listen prompt: prompts, options: %w{yes no}
            end
          end
        end
      end
    end
  end
end
