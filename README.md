# adhearsion-asr

Adds speech recognition support to Adhearsion as a plugin. Overrides `CallController#ask` and `#menu` to pass all recognition responsibility to the recognizer instead of invoking it multiple times.

## Features

* #ask API from Adhearsion core supporting digit limits, terminators, timeouts, inline grammars and grammar references
* #menu API from Adhearsion core supporting DTMF input and recognition failure

## Install

Add the following entry to your Adhearsion application's Gemfile:

```ruby
gem 'adhearsion-asr'
```

Be sure to check out the plugin config by running `rake config:show` and adjust to your requirements.

## Examples

### Simple collection of 5 DTMF digits

```ruby
class MyController < Adhearsion::CallController
  include AdhearsionASR::ControllerMethods

  def run
    result = ask limit: 5
    case result.status
    when :match
      speak "You entered #{result.utterance}"
    when :noinput
      speak "Hellooo? Anyone there?"
    when :nomatch
      speak "That doesn't make sense."
    end
  end
end
```

### Collecting an arbitrary number of digits until '#' is received:

```ruby
class MyController < Adhearsion::CallController
  include AdhearsionASR::ControllerMethods

  def run
    result = ask terminator: '#'
    case result.status
    when :match
      speak "You entered #{result.utterance}"
    when :noinput
      speak "Hellooo? Anyone there?"
    when :nomatch
      speak "That doesn't make sense."
    end
  end
end
```

### Collecting input from an inline speech grammar

```ruby
class MyController < Adhearsion::CallController
  include AdhearsionASR::ControllerMethods

  def run
    grammar = RubySpeech::GRXML.draw root: 'main', language: 'en-us', mode: :voice do
      rule id: 'main', scope: 'public' do
        one_of do
          item { 'yes' }
          item { 'no' }
        end
      end
    end

    result = ask grammar: grammar, input_options: { mode: :speech }
    case result.status
    when :match
      speak "You said #{result.utterance}"
    when :noinput
      speak "Hellooo? Anyone there?"
    when :nomatch
      speak "That doesn't make sense."
    end
  end
end
```

### Collecting input from a speech grammar by URL

```ruby
class MyController < Adhearsion::CallController
  include AdhearsionASR::ControllerMethods

  def run
    result = ask grammar_url: 'http://example.com/mygrammar.grxml', input_options: { mode: :speech }
    case result.status
    when :match
      speak "You said #{result.utterance}"
    when :noinput
      speak "Hellooo? Anyone there?"
    when :nomatch
      speak "That doesn't make sense."
    end
  end
end
```

### Executing a DTMF menu

```ruby
class MyController < Adhearsion::CallController
  def run
    answer
    menu "Where can we take you today?", timeout: 8.seconds, tries: 3 do
      match 1, BooController
      match '2', MyOtherController
      match(3, 4) { pass YetAnotherController }
      match 5, FooController
      match 6..10 do |dialed|
        say_dialed dialed
      end

      timeout { do_this_on_timeout }

      invalid do
        invoke InvalidController
      end

      failure do
        speak 'Goodbye'
        hangup
      end
    end

    speak "This code gets executed unless #pass is used"
  end

  def say_dialed(dialed)
    speak "#{dialed} was dialed"
  end

  def do_this_on_timeout
    speak 'Timeout'
  end
end
```

Check out the [API documentation](http://rdoc.info/gems/adhearsion-asr/frames) for more details.

## Links:
* [Source](https://github.com/adhearsion/adhearsion-asr)
* [Documentation](http://rdoc.info/gems/adhearsion-asr/frames)
* [Bug Tracker](https://github.com/adhearsion/adhearsion-asr/issues)

## Author

[Ben Langfeld](https://github.com/benlangfeld)

### Contributions

Adhearsion has a set of [contribution guidelines](https://github.com/adhearsion/adhearsion/wiki/Contributing) which help to smooth the contribution process.

### Copyright

Copyright (c) 2013 Adhearsion Foundation Inc. MIT LICENSE (see LICENSE for details).
