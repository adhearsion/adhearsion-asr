module AdhearsionASR
  Result = Struct.new(:status, :mode, :confidence, :response, :interpretation, :nlsml) do
    def to_s
      response
    end

    def inspect
      "#<#{self.class} status=#{status.inspect}, confidence=#{confidence.inspect}, response=#{response.inspect}, interpretation=#{interpretation.inspect}, nlsml=#{nlsml.inspect}>"
    end

    def response=(other)
      self[:response] = mode == :dtmf ? parse_dtmf(other) : other
    end

    private

    def parse_dtmf(dtmf)
      return if dtmf.nil? || dtmf.empty?
      dtmf.split(' ').inject '' do |final, digit|
        final << parse_dtmf_digit(digit)
      end
    end

    # @private
    def parse_dtmf_digit(digit)
      case tone = digit.split('-').last
      when 'star'
        '*'
      when 'pound'
        '#'
      else
        tone
      end
    end
  end
end
