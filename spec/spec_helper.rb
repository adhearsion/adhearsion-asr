require 'adhearsion'
require 'adhearsion-asr'

RSpec.configure do |config|
  config.color_enabled = true
  config.tty = true

  config.mock_with :rspec
  config.filter_run :focus => true
  config.run_all_when_everything_filtered = true

  config.backtrace_clean_patterns = [/rspec/]

  config.before do
    Punchblock.stub new_request_id: 'foo'
  end
end
