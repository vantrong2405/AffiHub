# frozen_string_literal: true

class Contents::GeneratedCopySanitizer
  URL_PATTERN = %r{https?://[^\s<>"']+}i

  # Removes provider-generated URLs so only the application's source link is attached separately.
  #
  # @param body [String, nil] copy returned by the AI provider
  # @return [String] copy with HTTP and HTTPS URLs removed
  def self.call(body:)
    body.to_s.gsub(URL_PATTERN, " ").gsub(/[ \t]{2,}/, " ").gsub(/ *\n */, "\n").gsub(/\n{3,}/, "\n\n").strip
  end
end
