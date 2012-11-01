# adhearsion-asr

Adds speech recognition support to Adhearsion as a plugin.

## Features

* Simple collection of spoken input

## Install

`gem install adhearsion-asr`

## Examples

```ruby
class MyController < Adhearsion::CallController
  include AdhearsionASR::ControllerMethods

  def run
    result = listen options: %w{yes no}
    speak "You said #{result.response}"
  end
end
```

## Links:
* [Source](https://github.com/adhearsion/adhearsion-asr)
* [Documentation](http://rdoc.info/github/adhearsion/adhearsion-asr/master/frames)
* [Bug Tracker](https://github.com/adhearsion/adhearsion-asr/issues)

## Author

[Ben Langfeld](https://github.com/benlangfeld)

### Contributions

Adhearsion has a set of [contribution guidelines](https://github.com/adhearsion/adhearsion/wiki/Contributing) which help to smooth the contribution process.

### Copyright

Copyright (c) 2012 Adhearsion Foundation Inc. MIT LICENSE (see LICENSE for details).
