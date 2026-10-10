class ApplicationService
  include ActiveModel::Model

  # Reports whether the last service call completed without validation errors.
  #
  # @return [Boolean] whether the service succeeded
  def success?
    @success == true && errors.empty?
  end

  private

  def step_succeed!
    @success = true
  end

  def step_fail!(message)
    errors.add(:base, message)
    @success = false
  end
end
