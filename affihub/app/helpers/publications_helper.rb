module PublicationsHelper
  # Renders the provider-specific consent fields for a Publication.
  #
  # @param presenter [Publications::ConsentPresenter] the prepared consent form state
  # @return [ActiveSupport::SafeBuffer, nil] rendered fields when required by the provider
  def render_publication_consent_fields(presenter)
    return if presenter.consent_partial.blank?

    render presenter.consent_partial, presenter:
  end
end
