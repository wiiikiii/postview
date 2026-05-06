class Database < ActiveRecord::Base
  self.table_name  = "pg_database"
  self.primary_key = "oid"

  def self.object_classify_name(name)
    name.gsub(/[-.]/, "_").classify
  end

  # Returns the sorted list of original table name strings.
  def self.tables_for(database_name)
    ensure_namespace(database_name)
    db_module = const_get(object_classify_name(database_name))
    return db_module.instance_variable_get(:@table_names) if db_module.instance_variable_defined?(:@table_names)

    table_names = []
    begin
      db_module::Connect.connection.tables.sort.each do |table|
        const = object_classify_name(table)
        unless db_module.const_defined?(const, false)
          klass = Class.new(db_module::Connect)
          db_module.const_set(const, klass)
          klass.table_name  = table
          klass.primary_key = nil
        end
        table_names << table
      end
    rescue => e
      Rails.logger.error "tables_for(#{database_name}): #{e.message}"
    end

    db_module.instance_variable_set(:@table_names, table_names)
    table_names
  end

  # Returns the ActiveRecord model class for a specific table.
  def self.model_for(database_name, table_name)
    tables_for(database_name)
    db_module = const_get(object_classify_name(database_name))
    db_module.const_get(object_classify_name(table_name), false)
  end

  private

  def self.ensure_namespace(database_name)
    ns = object_classify_name(database_name)
    return if const_defined?(ns)

    config = ActiveRecord::Base.connection_db_config.configuration_hash
               .merge(database: database_name)

    mod = Module.new
    const_set(ns, mod)

    connect = Class.new(ActiveRecord::Base) do
      self.table_name  = "pg_database"
      self.primary_key = "oid"
    end
    mod.const_set(:Connect, connect)
    connect.establish_connection(config)
  end
end
