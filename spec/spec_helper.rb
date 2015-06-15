require 'adhearsion'
require 'adhearsion-asr'

RSpec.configure do |config|
  config.color = true
  config.tty = true

  config.mock_with :rspec
  config.filter_run :focus => true
  config.run_all_when_everything_filtered = true

  config.backtrace_exclusion_patterns = [/rspec/]

  config.before do
    @current_datetime = DateTime.now
    allow(DateTime).to receive(:now).and_return(@current_datetime)

    allow(Punchblock).to receive(:new_request_id).and_return('foo')
  end
end
