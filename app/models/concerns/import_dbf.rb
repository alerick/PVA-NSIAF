module ImportDbf
  extend ActiveSupport::Concern

  CORRELATIONS = Hash.new

  included do
    unless self.const_defined?(:CORRELATIONS)
      self.const_set :CORRELATIONS, ImportDbf::CORRELATIONS
    end
  end

  module ClassMethods
    ##
    # Importar el archivo DBF a la tabla de usuarios
    def import_dbf(dbf)
      users = DBF::Table.new(dbf.tempfile)
      i = j = n = 0
      transaction do
        users.each_with_index do |record, index|
          print "#{index + 1}.-\t"
          if record.present?
            self.const_get(:CORRELATIONS).each { |k, v| print "#{record[k].inspect}, " }
            save_correlations(record) ? i += 1 : n += 1
          else
            j += 1
            print record.inspect
          end
          puts ''
        end
      end
      [i, n, j] # insertados, no insertados, nils
    end

    def to_csv(column_names)
      CSV.generate do |csv|
        csv << column_names
        all.each do |product|
          csv << product.attributes.values_at(*column_names)
        end
      end
    end

    private

    ##
    # Guarda en la base de datos de acuerdo a la correspondencia de campos.
    def save_correlations(record)
      import_data = Hash.new
      self.const_get(:CORRELATIONS).each do |origin, destination|
        import_data.merge!({ destination => record[origin] })
      end
      import_data.present? && self.new(import_data).save
    end
  end
end
