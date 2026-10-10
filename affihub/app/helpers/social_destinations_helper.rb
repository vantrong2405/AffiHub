module SocialDestinationsHelper
  # Returns whether a destination can be selected and the explanation shown to the user.
  #
  # @param provider [String] the social provider owning the destination
  # @param destination [Hash] the destination details returned by the index service
  # @return [Hash{Symbol => Boolean, String, nil}] selection state, badge label, and warning
  def social_destination_availability(provider, destination)
    return { selectable: true, status_label: nil, warning: nil } if provider == "youtube"

    unless destination.fetch("can_create_content")
      return {
        selectable: false,
        status_label: "Thiếu quyền",
        warning: "Page chưa cấp quyền tạo nội dung."
      }
    end

    if provider == "instagram" && !destination.fetch("instagram_account_eligible")
      return {
        selectable: false,
        status_label: "Không hỗ trợ tài khoản này",
        warning: instagram_destination_warning(destination)
      }
    end

    { selectable: true, status_label: "Được quyền tạo nội dung", warning: nil }
  end

  private

  def instagram_destination_warning(destination)
    instagram_business_account_id = destination.fetch("instagram_business_account_id")
    return "Page chưa liên kết Instagram Business account." if instagram_business_account_id.blank?

    "MVP chỉ hỗ trợ Instagram Business. Account type hiện tại: #{destination.fetch("instagram_account_type")}."
  end
end
