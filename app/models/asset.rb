class Asset < ActiveRecord::Base
  include ImportDbf, Migrated, VersionLog, ManageStatus
  include Moneda
  include Autoincremento

  CORRELATIONS = {
    'CODIGO' => 'code',
    'DESCRIP' => 'description',
    'CODESTADO' => 'state',
    'OBSERV' => 'observation'
  }

  STATE = {
    'Bueno' => '1',
    'Regular' => '2',
    'Malo' => '3'
  }

  belongs_to :auxiliary
  belongs_to :user, counter_cache: true
  belongs_to :ingreso
  belongs_to :ubicacion

  has_many :asset_proceedings
  has_many :proceedings, through: :asset_proceedings
  has_many :cierre_gestiones
  has_many :gestiones, through: :cierre_gestiones

  scope :assigned, -> { where.not(user_id: nil) }
  scope :unassigned, -> { where(user_id: nil) }

  with_options if: :is_not_migrate? do |m|
    # m.validates :barcode, presence: true, uniqueness: true
    m.validates :code, presence: true, uniqueness: true
    m.validates :detalle, :auxiliary_id, :user_id, :precio, presence: true
    # TODO validación de los códigos de barras desactivado.
    # m.validate do |asset|
    #   BarcodeStatusValidator.new(asset).validate  has_many :proceedings, through: :asset_proceedingsbuscarasset_proceedingsbuscar
    # end
  end

  with_options if: :is_migrate? do |m|
    m.validates :code, presence: true, uniqueness: true
    m.validates :description, presence: true
  end

  before_save :establecer_barcode
  before_save :check_barcode
  before_save :generar_descripcion

  has_paper_trail

  def self.busqueda_basica(col, q, cuentas, desde, hasta)
    activos = self.select("assets.id as id, assets.code as codigo, assets.description as descripcion, assets.precio as precio, ingresos.factura_numero as factura, ingresos.factura_fecha as fecha_ingreso, accounts.name as cuenta")
                  .joins("LEFT JOIN ingresos ON assets.ingreso_id = ingresos.id")
                  .joins(auxiliary: [:account])
    if q.present? || cuentas.present? || (desde.present? && hasta.present?) || col.present?
      if q.present?
        if col == 'all'
          activos = activos.where("assets.description like :q OR assets.code like :code OR ingresos.factura_numero like :nf", q: "%#{q}%", code: "%#{q}%", nf: "%#{q}%")
        else
          case col
          when 'code'
            activos = activos.where("assets.code like :q", q: "%#{q}%")
          when 'description'
            activos = activos.where("assets.description like :q", q: "%#{q}%")
          when 'invoice'
            activos = activos.where("ingresos.factura_numero = :q", q: q)
          end
        end
      end
      if cuentas.present?
        activos = activos.where("accounts.id = :c", c: cuentas)
      end
      if desde.present? && hasta.present?
        activos = activos.where("ingresos.factura_fecha" => desde..hasta)
      end
    end
    activos
  end

  def self.busqueda_avanzada(codigo, numero_factura, descripcion, cuenta, precio, desde, hasta)
    activos = self.select("assets.id as id, assets.code as codigo, assets.description as descripcion, assets.precio as precio, ingresos.factura_numero as factura, ingresos.factura_fecha as fecha_ingreso, accounts.name as cuenta")
                  .joins("LEFT JOIN ingresos ON assets.ingreso_id = ingresos.id")
                  .joins(auxiliary: [:account])
    if codigo.present?
      activos = activos.where("assets.code = :co", co: codigo)
    end
    if numero_factura.present?
      activos = activos.where("ingresos.factura_numero = :nf", nf: numero_factura)
    end
    if descripcion.present?
      activos = activos.where("assets.description = :de", de: descripcion)
    end
    if precio.present?
      activos = activos.where("accounts.id = :pr", pr: precio)
    end
    if cuenta.present?
      activos = activos.where("accounts.id = :cu", cu: cuenta)
    end
    if desde.present? && hasta.present?
      activos = activos.where("ingresos.factura_fecha" => desde..hasta)
    end
    activos
  end

  def self.buscar_por_barcode(barcode)
    barcodes = barcode.split(',').map(&:strip)
    barcodes.map! do |rango|
      guiones = rango.split('-').map(&:strip)
      guiones.length > 1 ? Array(guiones[0].to_i..guiones[1].to_i).map(&:to_s) : guiones
    end
    where(barcode: barcodes.flatten.uniq).order(:code)
  end

  #agregados
  def self.buscar_barcode_to_pdf(barcode)
    barcodes = barcode.split(',').map(&:strip)
    arrayVal = Array.new
    barcodes.map! do |rango|
      guiones = rango.split('-').map(&:strip)
      guiones.length > 1 ? Array(guiones[0].to_i..guiones[1].to_i).map(&:to_s) : guiones
    end
    barcodes.each do |x|
      if x[0].include?("x")
        mult = x[0].split('x').map(&:to_i)
        for i in 1..mult[0]
          activos = where(barcode: mult[1])
          arrayVal += activos
        end
      end
      activos = where(barcode: x.flatten)
      arrayVal += activos
    end
    arrayVal
  end

  def self.derecognised
    where(status: 0)
  end

  # Método para obtener el siguiente codigo de activo.
  def self.obtiene_siguiente_codigo
    Asset.all.empty? ? 1 : Asset.maximum(:code) + 1
  end

  def self.historical_assets(user)
    includes(:user).joins(:asset_proceedings).where(asset_proceedings: {proceeding_id: user.proceeding_ids})
  end

  def auxiliary_code
    auxiliary.present? ? auxiliary.code : ''
  end

  def auxiliary_name
    auxiliary.present? ? auxiliary.name : ''
  end

  def account
    auxiliary.present? ? auxiliary.account : nil
  end

  def account_code
    auxiliary.present? ? auxiliary.account_code : ''
  end

  def account_name
    auxiliary.present? ? auxiliary.account_name : ''
  end

  def change_barcode_to_deleted
    if self.barcode_was.present? && self.barcode_was != self.barcode
      bc = Barcode.find_by_code barcode_was
      bc.change_to_deleted if bc.present?
    end
  end

  def establecer_barcode
    self.barcode = self.code
  end

  def check_barcode
    if is_not_migrate?
      bcode = Barcode.find_by_code barcode
      if bcode.present?
        self.barcode = bcode.code
        bcode.change_to_used
      end
      change_barcode_to_deleted
    end
  end

  # Fecha de ingreso del activo fijo
  def ingreso_fecha
    ingreso.present? ? ingreso.factura_fecha : nil
  end

  def ingreso_proveedor
    ingreso.present? ? ingreso.supplier : nil
  end

  # Fecha de ingreso del activo fijo
  def ingreso_proveedor_nombre
    ingreso.present? ? ingreso.supplier_name : nil
  end

  def nro_factura
    ingreso.present?  ? ingreso.factura_numero : nil
  end

  def name
    description
  end

  def user_code
    user.present? ? user.code : ''
  end

  def user_name
    user.present? ? user.name : ''
  end

  def self.set_columns
    h = ApplicationController.helpers
    [h.get_column(self, 'code'), h.get_column(self, 'code_old'), h.get_column(self, 'description'), h.get_column(self, 'incorporacion'), h.get_column(self, 'supplier'), h.get_column(self, 'account'), h.get_column(self, 'user'), h.get_column(self, 'ubicacion')]
  end

  def self.without_barcode
    where("barcode IS NULL OR barcode = ''")
  end

  def self.without_user
    where(user_id: nil)
  end

  def verify_assignment
    false
  end

  def self.array_model(sort_column, sort_direction, page, per_page, sSearch, search_column, status)
    array = includes(:ingreso, :user, :ubicacion, ingreso: :supplier, auxiliary: :account).order("#{sort_column} #{sort_direction}").where(status: status).references(auxiliary: :account)
    array = array.page(page).per_page(per_page) if per_page.present?
    if sSearch.present?
      if search_column.present?
        if search_column == 'account'
          array = array.where('accounts.name LIKE ?', "%#{sSearch}%")
        elsif search_column == 'incorporacion' # modelo: Ingreso
          array = array.where('ingresos.factura_fecha LIKE ?', "%#{convertir_fecha(sSearch)}%")
        elsif search_column == 'supplier' # modelo: Supplier / Proveedor
          array = array.where('suppliers.name LIKE ?', "%#{sSearch}%")
        elsif search_column == 'ubicacion' # modelo: Ubicacion
          array = array.where('ubicaciones.abreviacion LIKE ?', "%#{sSearch}%")
        else
          type_search = search_column == 'user' ? 'users.name' : "assets.#{search_column}"
          array = array.where("#{type_search} like :search", search: "%#{sSearch}%")
        end
      else
         array = array.where("assets.code LIKE ? OR assets.code_old LIKE ? OR assets.description LIKE ? OR users.name LIKE ? OR accounts.name LIKE ? OR suppliers.name LIKE ? OR ingresos.factura_fecha LIKE ? OR ubicaciones.abreviacion LIKE ?", "%#{sSearch}%", "%#{sSearch}%", "%#{sSearch}%", "%#{sSearch}%", "%#{sSearch}%", "%#{sSearch}%", "%#{convertir_fecha(sSearch)}%", "%#{sSearch}%")
      end
    end
    array
  end

  def self.to_csv(is_low = false)
    columns = %w(code description user ubicacion)
    columns_title = columns
    columns_title += %w(derecognised) if is_low
    CSV.generate do |csv|
      csv << columns_title.map { |c| self.human_attribute_name(c) }
      all.each do |asset|
        a = asset.attributes.values_at(*columns).compact
        a.push(asset.user_name)
        a.push(asset.ubicacion_detalle)
        a.push(I18n.l(asset.derecognised, format: :version)) if asset.derecognised.present?
        csv << a
      end
    end
  end

  def self.total_historico
    all.sum(:precio)
  end

  def derecognised_date
    update_attribute(:derecognised, Time.now)
  end

  def get_state
    case state
    when 1 then 'Bueno'
    when 2 then 'Regular'
    when 3 then 'Malo'
    end
  end

  ##
  ## BEGIN Los campos de la tabla para el reporte de Depreciación de Activos Fijos

  def revaluo_inicial
    # TODO completar de acuerdo a lo requerido
    'N'
  end

  # UFV inicial en base a la fecha de compra o ingreso
  def indice_ufv
    ingreso_fecha.present? ? Ufv.indice(ingreso_fecha) : 0
  end

  # Costo histórico con el que se compró el activo fijo
  def costo_historico
    # TODO cuando hay revalúos hay cambio, actualmente no está considerado
    precio
  end

  # Costo actualizado inicial
  def costo_actualizado_inicial(fecha = Date.today)
    ag = cierre_gestiones.where('fecha < ?', fecha).sum(:actualizacion_gestion)
    costo_historico + ag
  end

  def depreciacion_acumulada_inicial(fecha = Date.today)
    cierre_gestiones.where('fecha < ?', fecha).sum(:depreciacion_gestion)
  end

  # Vida útil del activo fijo
  def vida_util_residual_nominal
    auxiliary.present? ? auxiliary.account_vida_util : 0
  end

  def factor_actualizacion(fecha = Date.today)
    cg = cierre_gestiones.where('fecha < ?', fecha).order(:fecha).last
    ufv = cg.present? ? cg.indice_ufv : indice_ufv
    Ufv.indice(fecha) / ufv
  end

  def actualizacion_gestion(fecha = Date.today)
    costo_actualizado(fecha) - costo_actualizado_inicial(fecha)
  end

  def costo_actualizado(fecha = Date.today)
    costo_actualizado_inicial(fecha) * factor_actualizacion(fecha)
  end

  def porcentaje_depreciacion_anual
    100 / vida_util_residual_nominal.to_f
  end

  # Días desde la adquisición del activo fijo
  def dias_consumidos(fecha = Date.today)
    (fecha - ingreso_fecha).to_i + 1 rescue 0
  end

  # Días desde el último cierre de gestión
  def dias_consumidos_ultimo(fecha = Date.today)
    cg = cierre_gestiones.where('fecha < ?', fecha).order(:fecha).last
    cg.present? ? (fecha - cg.fecha).to_i : dias_consumidos(fecha)
  end

  def depreciacion_gestion(fecha = Date.today)
    costo_actualizado(fecha) / 365.0 * dias_consumidos_ultimo(fecha) * porcentaje_depreciacion_anual / 100.0
  end

  def actualizacion_depreciacion_acumulada(fecha = Date.today)
    depreciacion_acumulada_inicial(fecha) * (factor_actualizacion(fecha) - 1)
  end

  def depreciacion_acumulada_total(fecha = Date.today)
    costo_actualizado(fecha) / 365 * dias_consumidos(fecha) * porcentaje_depreciacion_anual / 100
  end

  def valor_neto(fecha = Date.today)
    # El método redondear es un requisito para igualar a los resultados emitidos
    # por el sistema vSIAF del ministerio
    redondear(costo_actualizado(fecha)) - redondear(depreciacion_acumulada_total(fecha))
  end

  def dar_revaluo_o_baja
    # TODO cuando el activo está de baja o se haya revaluado
    'NO'
  end

  def self.costo_historico
    all.inject(0) { |s, a| redondear(a.costo_historico) + s }
  end

  def self.costo_actualizado_inicial(fecha = Date.today)
    all.inject(0) { |s, a| redondear(a.costo_actualizado_inicial(fecha)) + s }
  end

  def self.depreciacion_acumulada_inicial(fecha = Date.today)
    all.inject(0) { |s, a| redondear(a.depreciacion_acumulada_inicial(fecha)) + s }
  end

  def self.actualizacion_gestion(fecha = Date.today)
    all.inject(0) { |s, a| redondear(a.actualizacion_gestion(fecha)) + s }
  end

  def self.costo_actualizado(fecha = Date.today)
    all.inject(0) { |s, a| redondear(a.costo_actualizado(fecha)) + s }
  end

  def self.depreciacion_gestion(fecha = Date.today)
    all.inject(0) { |s, a| redondear(a.depreciacion_gestion(fecha)) + s }
  end

  def self.actualizacion_depreciacion_acumulada(fecha = Date.today)
    all.inject(0) { |s, a| redondear(a.actualizacion_depreciacion_acumulada(fecha)) + s }
  end

  def self.depreciacion_acumulada_total(fecha = Date.today)
    all.inject(0) { |s, a| redondear(a.depreciacion_acumulada_total(fecha)) + s }
  end

  def self.valor_neto(fecha = Date.today)
    all.inject(0) { |s, a| redondear(a.valor_neto(fecha)) + s }
  end

  ## END Los campos de la tabla para el reporte de Depreciación de Activos Fijos
  ##

  ##
  # Cerrar gestión actual de los subartículos
  def self.cerrar_gestion_actual(fecha = Date.today)
    activos = includes(:ingreso)
    activos = activos.where("ingresos.factura_fecha <= ?", fecha).references(:ingreso)
    self.transaction do
      activos.each do |activo|
        activo.cerrar_gestion_actual(fecha)
      end
    end
  end

  # Inserta un nuevo registro en la tabla cierre_gestiones
  def cerrar_gestion_actual(fecha = Date.today)
    gestion = Gestion.find_by(anio: fecha.year)
    activo = self
    cierre_gestion = CierreGestion.find_by(asset: activo, gestion: gestion)
    unless cierre_gestion.present?
      cierre_gestion = CierreGestion.new(asset: activo, gestion: gestion)
      cierre_gestion.actualizacion_gestion = activo.actualizacion_gestion(fecha)
      cierre_gestion.depreciacion_gestion = activo.depreciacion_gestion(fecha)
      cierre_gestion.indice_ufv = Ufv.indice(fecha)
      cierre_gestion.fecha = fecha
      cierre_gestion.save!
    end
  end

  def ubicacion_abreviacion
    ubicacion.present? ? ubicacion.abreviacion : ''
  end

  def ubicacion_descripcion
    ubicacion.present? ? ubicacion.descripcion : ''
  end

  def ubicacion_detalle
    ubicacion.present? ? ubicacion.detalle : ''
  end

  # método que verifica si el activo tiene un código.
  def tiene_codigo?
    code.present?
  end

  private

  ##
  # Guarda en la base de datos de acuerdo a la correspondencia de campos.
  def self.save_correlations(record)
    asset = { is_migrate: true }
    CORRELATIONS.each do |origin, destination|
      asset.merge!({ destination => record[origin] })
    end
    ac = Account.find_by_code(record['CODCONT'])
    ax = Auxiliary.joins(:account).where(code: record['CODAUX'], accounts: { code: record['CODCONT'] }).take
    u = User.joins(:department).where(code: record['CODRESP'], departments: { code: record['CODOFIC'] }).take
    asset.present? && new(asset.merge!({ account: ac, auxiliary: ax, user: u })).save
  end

  ##
  # Permite convertir una fecha en string a un formato para búsqueda en base de datos
  # p.e. 30-03-2016 => 2016-03-30, 30-03 => 03-30, 30/03/2016 => 2016-03-30, 30/03 => 03-30
  def self.convertir_fecha(fecha)
    unless fecha =~ /[^0-9|\/|-]/
      return fecha.split('/').reverse.join('-') if fecha =~ /\//
      return fecha.split('-').reverse.join('-') if fecha =~ /-/
      return fecha.strip unless fecha =~ /[^0-9]/
    end
    return fecha
  end

  def generar_descripcion
    descripcion = []
    descripcion << detalle if detalle.strip.present?
    descripcion << "MEDIDAS #{medidas}" if medidas.strip.present?
    descripcion << "MATERIAL #{material}" if material.strip.present?
    descripcion << "COLOR #{color}" if color.strip.present?
    descripcion << "MARCA #{marca}" if marca.strip.present?
    descripcion << "MODELO #{modelo}" if modelo.strip.present?
    descripcion << "SERIE #{serie}" if serie.strip.present?
    self.description = descripcion.join(' ').squish
  end
end
