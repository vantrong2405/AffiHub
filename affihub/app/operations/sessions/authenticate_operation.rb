# frozen_string_literal: true

class Sessions::AuthenticateOperation < MainOperation
  def initialize(params:)
    super
    @form = SessionForm.new(params.slice(:email, :password))
  end

  def call
    step_validate_credentials
    step_find_user unless error?
    step_create_session! unless error?
  end

  private

  def step_validate_credentials
    form.valid?
  end

  def step_find_user
    @user = User.find_by(email: form.email)
    return if @user&.authenticate(form.password)

    @user = nil
    form.errors.add(:base, "Invalid email or password")
  end

  def step_create_session!
    params[:session][:user_id] = @user.id
  end
end
