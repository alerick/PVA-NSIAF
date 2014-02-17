class DashboardController < ApplicationController
  def index
    @user = current_user
  end

  def update_password
    @user = User.find(current_user.id)
    if @user.update_with_password(user_params)
      sign_in @user, bypass: true
      redirect_to dashboard_url, notice: 'Su contraseña se actualizó correctamente'
    else
      render "index"
    end
  end

  private

  def user_params
    params.required(:user).permit(:current_password, :password, :password_confirmation)
  end
end