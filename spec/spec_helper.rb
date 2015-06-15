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
    DateTime.stub now: @current_datetime

    Punchblock.stub new_request_id: 'foo'
  end
end
