# [develop](https://github.com/adhearsion/adhearsion-asr)

# [v1.1.1](https://github.com/adhearsion/adhearsion-asr/compare/1.1.0...1.1.1) - [2014-01-28](https://rubygems.org/gems/adhearsion-asr/versions/1.1.1)
  * Bugfix: Handle stop completion reason smoothly

# [v1.1.0](https://github.com/adhearsion/adhearsion-asr/compare/1.0.1...1.1.0) - [2014-01-02](https://rubygems.org/gems/adhearsion-asr/versions/1.1.0)
  * Feature: Alias `Result#response` to `#utterance`, with a deprecation warning
  * Feature: Add `#match?` predicate to `Result` object
  * Feature: When no prompts are supplied, only execute an input component

# [v1.0.1](https://github.com/adhearsion/adhearsion-asr/compare/1.0.0...1.0.1) - [2013-09-30](https://rubygems.org/gems/adhearsion-asr/versions/1.0.1)
  * Bugfix: A menu definition's block context is now available

# [v1.0.0](https://github.com/adhearsion/adhearsion-asr/compare/0.1.0...1.0.0) - [2013-08-29](https://rubygems.org/gems/adhearsion-asr/versions/1.0.0)
  * Change: Controller methods are now included in all call controllers by default, but this is configurable
  * Change: Default renderer/voice config is moved to Adhearsion core
  * Change: `Result#response` is now `#utterance`
  * Bugfix: DTMF input is now sanitized to remove spaces and `dtmf-` prefixes
  * Bugfix: Function correctly on upcoming Adhearsion/Punchblock releases

# [v0.1.0](https://github.com/adhearsion/adhearsion-asr/compare/6216ddb0a8b8c0ac5d1731ec154fe6d6abfea692...0.1.0) - [2013-05-07](https://rubygems.org/gems/adhearsion-asr/versions/0.1.0)
  * Feature: #ask and #menu from Adhearsion core
    * Mostly API compatible, with some very minor differences
    * Use Rayo Prompt component
    * Support for arbitrary grammars (ASR) in #ask
