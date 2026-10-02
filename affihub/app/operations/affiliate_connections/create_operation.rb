# frozen_string_literal: true

class AffiliateConnections::CreateOperation < MainOperation
  # @return [AffiliateConnection, nil] the saved connection after a successful #call
  attr_reader :affiliate_connection

  # @param params [Hash] :current_user (required), :api_key (required)
  # @return [void]
  def initialize(params:)
    super
    @errors = ActiveModel::Errors.new(self)
    @form = AffiliateConnections::CreateForm.new(params.slice(:api_key))
    @errors = @form.errors
  end

  # Validates and stores the current user's encrypted ACCESSTRADE API token.
  #
  # @return [void]
  def call
    return unless form.valid?

    @affiliate_connection = current_user.affiliate_connection || current_user.build_affiliate_connection
    @affiliate_connection.provider = "accesstrade"
    @affiliate_connection.api_key = form.api_key
    @affiliate_connection.save!
  rescue ActiveRecord::RecordInvalid => error
    error.record.errors.each { |attribute, message| errors.add(attribute, message) }
  end
end
