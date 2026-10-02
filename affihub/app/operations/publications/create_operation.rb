# frozen_string_literal: true

class Publications::CreateOperation < MainOperation
  attr_reader :publication

  # @param params [Hash] :current_user, :content_id, and :social_destination_id
  # @return [void]
  def initialize(params:)
    super
    @errors = ActiveModel::Errors.new(self)
    @form = Publications::CreateForm.new(params)
  end

  # Creates a draft only for approved owned content and an owned Page destination.
  #
  # @return [void]
  def call
    step_validate_form
    step_create_publication unless error?
  end

  private

  # Validates the ownership and lifecycle rules before persistence.
  #
  # @return [void]
  def step_validate_form
    errors.add(:base, @form.errors.full_messages.to_sentence) unless @form.valid?
  end

  # Persists a draft Publication linked to the selected Page.
  #
  # @return [void]
  def step_create_publication
    @publication = Publication.new(content: @form.content, social_destination: @form.social_destination, status: :draft)
    errors.add(:base, @publication.errors.full_messages.to_sentence) unless @publication.save
  end
end
