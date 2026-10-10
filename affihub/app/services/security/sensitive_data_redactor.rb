class Security::SensitiveDataRedactor
  REDACTION_MARKER = "[FILTERED]"
  SENSITIVE_KEY = /(?:authorization|oauth[_-]?(?:code|state)|code[_-]?verifier|(?:^|[_-])state(?:$|[_-])|access[_-]?token|refresh[_-]?token|token|secret|password|api[_-]?key|access[_-]?key|signed|session|upload[_-]?(?:uri|url))/i
  SENSITIVE_QUERY_PARAMETER = /(?:authorization|oauth[_-]?(?:code|state)|code[_-]?verifier|(?:^|[_-])(?:code|state)(?:$|[_-])|token|secret|password|api[_-]?key|access[_-]?key|upload[_-]?id|signature|(?:^|[_-])sig(?:$|[_-])|session|credential)/i

  # Initializes the redactor with exact secret values known to the caller.
  #
  # @param secret_values [Array<String>] secret values that must be removed
  # @return [Security::SensitiveDataRedactor] the configured redactor
  def initialize(secret_values: [])
    @secret_values = secret_values.compact.map(&:to_s).reject(&:blank?)
  end

  # Returns a recursively copied value with secret fields and values filtered.
  #
  # @param value [Object] structured data or text to sanitize
  # @return [Object] sanitized data with the same outer structure
  def call(value)
    step_redact(value)
  end

  private

  def step_redact(value)
    case value
    when Hash
      value.to_h do |key, nested_value|
        [ key, step_sensitive_key?(key) ? REDACTION_MARKER : step_redact(nested_value) ]
      end
    when Array
      value.map { |nested_value| step_redact(nested_value) }
    when String
      step_redact_text(value.dup)
    else
      value
    end
  end

  def step_sensitive_key?(key)
    key.to_s.match?(SENSITIVE_KEY)
  end

  def step_redact_text(value)
    @secret_values.each do |secret|
      value.gsub!(Regexp.new(Regexp.escape(secret)), REDACTION_MARKER)
    end
    value.gsub!(/(Bearer\s+)[A-Za-z0-9._~+\/=:-]+/i, "\\1#{REDACTION_MARKER}")
    value.gsub!(/([?&][^=?&#]*[=])([^&#]*)/) do |query_parameter|
      parameter = query_parameter.split("=", 2).first
      step_sensitive_query_parameter?(parameter) ? "#{parameter}=#{REDACTION_MARKER}" : query_parameter
    end
    value
  end

  def step_sensitive_query_parameter?(parameter)
    parameter.delete_prefix("?").delete_prefix("&").match?(SENSITIVE_QUERY_PARAMETER)
  end
end
