module AdhearsionASR
  Result = Struct.new(:status, :confidence, :response, :interpretation, :nlsml) do
    def to_s
      response
    end

    def inspect
      "#<#{self.class} status=#{status.inspect}, confidence=#{confidence.inspect}, response=#{response.inspect}, interpretation=#{interpretation.inspect}, nlsml=#{nlsml.inspect}>"
    end
  end
end
