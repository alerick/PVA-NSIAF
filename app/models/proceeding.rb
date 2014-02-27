class Proceeding < ActiveRecord::Base
  PROCEEDING_TYPE = {
    'E' => 'assignation',
    'D' => 'devolution'
  }

  belongs_to :user
  belongs_to :admin, class_name: 'User'

  has_many :asset_proceedings
  has_many :assets, through: :asset_proceedings

  after_create :update_assignations

  def self.set_columns
   h = ApplicationController.helpers
   c_names = column_names - %w(id created_at updated_at proceeding_type)
   c_names.map{ |c| h.get_column(self, c) unless c == 'object' }.compact
  end

  def admin_name
    admin ? admin.name : ''
  end

  def get_type
    PROCEEDING_TYPE[proceeding_type]
  end

  ##
  # Tipo de Acta:
  #   E: Asignación, Entrega de Activos
  #   D: Devolución de Activos
  def is_assignation?
    proceeding_type == 'E'
  end

  def is_devolution?
    proceeding_type == 'D'
  end

  def user_name
    user ? user.name : ''
  end

  private

  def update_assignations
    user_id = self.admin_id
    user_id = self.user_id if is_assignation?
    assets.update_all(user_id: user_id)
  end
end