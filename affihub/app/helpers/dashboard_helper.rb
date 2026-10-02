# frozen_string_literal: true

module DashboardHelper
  # Returns a Vietnamese label for a publication lifecycle status.
  #
  # @param status [String] persisted Publication status
  # @return [String] user-facing status label
  def publication_status_label(status)
    {
      "draft" => "Bản nháp",
      "scheduled" => "Đã lên lịch",
      "publishing" => "Đang đăng",
      "published" => "Đã đăng",
      "failed" => "Thất bại"
    }.fetch(status, status.humanize)
  end

  # Returns semantic Tailwind classes for a publication lifecycle status.
  #
  # @param status [String] persisted Publication status
  # @return [String] badge background and text classes
  def publication_status_classes(status)
    {
      "published" => "bg-emerald-50 text-emerald-700",
      "failed" => "bg-red-50 text-red-700",
      "scheduled" => "bg-amber-50 text-amber-700",
      "publishing" => "bg-amber-50 text-amber-700"
    }.fetch(status, "bg-neutral-bg text-neutral")
  end
end
