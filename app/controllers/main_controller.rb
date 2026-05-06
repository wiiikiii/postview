class MainController < ApplicationController
  def index
    @databases = Database.all.order(:datname)
  end

  def database
    @database = params[:id]
    @tables   = Database.tables_for(@database)
  end

  def database_info
    @database = params[:id]
    c  = ActiveRecord::Base.connection
    q  = c.quote(@database)

    @info = c.execute(<<~SQL).first
      SELECT d.datname, d.oid::text,
             r.rolname                                        AS owner,
             pg_encoding_to_char(d.encoding)                 AS encoding,
             d.datcollate, d.datctype,
             t.spcname                                        AS tablespace,
             d.datconnlimit,
             pg_size_pretty(pg_database_size(d.datname))     AS size_pretty,
             pg_database_size(d.datname)                     AS size_bytes
      FROM   pg_database d
      LEFT JOIN pg_roles      r ON r.oid = d.datdba
      LEFT JOIN pg_tablespace t ON t.oid = d.dattablespace
      WHERE  d.datname = #{q}
    SQL
    return redirect_to root_path, alert: 'Datenbank nicht gefunden.' unless @info

    @stats = c.execute("SELECT * FROM pg_stat_database WHERE datname = #{q}").first

    @connections = c.execute(<<~SQL).first
      SELECT COUNT(*) FILTER (WHERE state = 'active') AS active,
             COUNT(*)                                  AS total
      FROM   pg_stat_activity
      WHERE  datname = #{q}
    SQL

    @max_connections = c.execute('SHOW max_connections').first['max_connections'].to_i

    @acl = c.execute(<<~SQL).to_a
      SELECT CASE WHEN grantee = 0 THEN 'PUBLIC'
                  ELSE grantee::regrole::text END     AS grantee,
             grantor::regrole::text                   AS grantor,
             privilege_type,
             is_grantable
      FROM  (SELECT (aclexplode(COALESCE(datacl, acldefault('d', datdba)))).*
             FROM   pg_database
             WHERE  datname = #{q}) t
      ORDER BY grantee, privilege_type
    SQL

    mod = Database.connect(@database)
    mod::Connect.with_connection do |dc|
      @schemas = dc.execute(<<~SQL).to_a
        SELECT n.nspname                                               AS name,
               r.rolname                                               AS owner,
               COUNT(c.oid) FILTER (WHERE c.relkind = 'r')            AS tables,
               COUNT(c.oid) FILTER (WHERE c.relkind = 'v')            AS views,
               COUNT(c.oid) FILTER (WHERE c.relkind = 'S')            AS sequences,
               COUNT(c.oid) FILTER (WHERE c.relkind = 'f')            AS foreign_tables
        FROM   pg_namespace n
        LEFT JOIN pg_roles r ON r.oid = n.nspowner
        LEFT JOIN pg_class c ON c.relnamespace = n.oid
        WHERE  n.nspname NOT LIKE 'pg_toast%'
          AND  n.nspname NOT LIKE 'pg_temp%'
        GROUP BY n.nspname, r.rolname
        ORDER BY n.nspname
      SQL
    end
  rescue => e
    redirect_to root_path, alert: "Fehler: #{e.message}"
  end

  def table_info
    @database = params[:db]
    @table    = params[:table]

    mod = Database.connect(@database)
    mod::Connect.with_connection do |dc|
      qt = dc.quote(@table)

      @stats = dc.execute(<<~SQL).first
        SELECT s.*,
               pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size_pretty,
               pg_size_pretty(pg_relation_size(c.oid))       AS table_size_pretty,
               pg_size_pretty(pg_indexes_size(c.oid))        AS index_size_pretty,
               pg_total_relation_size(c.oid)                 AS total_size_bytes,
               r.rolname                                      AS owner,
               COALESCE(ts.spcname, 'pg_default')            AS tablespace,
               n.nspname                                      AS schema_name
        FROM   pg_stat_user_tables s
        JOIN   pg_class c ON c.relname = s.relname
               AND c.relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = s.schemaname)
        LEFT JOIN pg_roles      r  ON r.oid  = c.relowner
        LEFT JOIN pg_tablespace ts ON ts.oid = c.reltablespace
        JOIN   pg_namespace     n  ON n.oid  = c.relnamespace
        WHERE  s.relname = #{qt}
        LIMIT 1
      SQL

      return redirect_to database_path(@database), alert: 'Tabelle nicht gefunden.' unless @stats

      @foreign_keys = dc.execute(<<~SQL).to_a
        SELECT kcu.column_name,
               ccu.table_name  AS foreign_table,
               ccu.column_name AS foreign_column,
               rc.update_rule,
               rc.delete_rule
        FROM   information_schema.table_constraints tc
        JOIN   information_schema.key_column_usage kcu
               ON  tc.constraint_name = kcu.constraint_name
               AND tc.table_schema    = kcu.table_schema
        JOIN   information_schema.referential_constraints rc
               ON  tc.constraint_name = rc.constraint_name
               AND tc.table_schema    = rc.constraint_schema
        JOIN   information_schema.constraint_column_usage ccu
               ON  ccu.constraint_name = rc.unique_constraint_name
               AND ccu.table_schema    = rc.unique_constraint_schema
        WHERE  tc.constraint_type = 'FOREIGN KEY'
          AND  tc.table_name = #{qt}
        ORDER BY kcu.column_name
      SQL

      @referenced_by = dc.execute(<<~SQL).to_a
        SELECT tc.table_name   AS from_table,
               kcu.column_name AS from_column,
               ccu.column_name AS to_column,
               rc.update_rule,
               rc.delete_rule
        FROM   information_schema.table_constraints tc
        JOIN   information_schema.key_column_usage kcu
               ON  tc.constraint_name = kcu.constraint_name
               AND tc.table_schema    = kcu.table_schema
        JOIN   information_schema.referential_constraints rc
               ON  tc.constraint_name = rc.constraint_name
               AND tc.table_schema    = rc.constraint_schema
        JOIN   information_schema.constraint_column_usage ccu
               ON  ccu.constraint_name = rc.unique_constraint_name
               AND ccu.table_schema    = rc.unique_constraint_schema
        WHERE  tc.constraint_type = 'FOREIGN KEY'
          AND  ccu.table_name = #{qt}
        ORDER BY tc.table_name, kcu.column_name
      SQL

      @indexes = dc.execute(<<~SQL).to_a
        SELECT i.relname                                      AS index_name,
               ix.indisprimary                               AS primary,
               ix.indisunique                                AS unique,
               pg_size_pretty(pg_relation_size(i.oid))       AS size,
               array_to_string(ARRAY(
                 SELECT pg_get_indexdef(ix.indexrelid, k, true)
                 FROM   generate_subscripts(ix.indkey, 1) AS k
               ), ', ')                                      AS columns
        FROM   pg_index ix
        JOIN   pg_class c ON c.oid = ix.indrelid
        JOIN   pg_class i ON i.oid = ix.indexrelid
        WHERE  c.relname = #{qt}
        ORDER BY ix.indisprimary DESC, i.relname
      SQL
    end
  rescue => e
    redirect_to database_path(@database), alert: "Fehler: #{e.message}"
  end

  def structure
    @database = params[:db]
    @table    = params[:table]
    model     = Database.model_for(@database, @table)
    @columns  = model.columns
    @pk       = Array(model.primary_key)
    @indexes  = model.connection.indexes(@table)
  rescue NameError
    redirect_to database_path(@database), alert: 'Table not found.'
  end

  def table
    @database    = params[:db]
    @table       = params[:table]
    @query       = params[:q].to_s.strip

    model        = Database.model_for(@database, @table)
    @columns     = model.column_names
    @pk          = Array(model.primary_key)
    @col_types   = model.columns.map { |c| [c.name, c.sql_type] }.to_h
    @rows        = filtered(model).page(params[:page]).per(25)
    @search_params = build_search_params
  rescue NameError
    redirect_to database_path(@database), alert: 'Table not found.'
  end

  def create_row
    @database = params[:db]
    @table    = params[:table]
    model     = Database.model_for(@database, @table)

    null_cols  = Array(params[:null_cols])
    row_params = params[:row]&.to_unsafe_h || {}

    attrs = {}
    row_params.each do |col, val|
      next unless model.column_names.include?(col)
      attrs[col] = val.presence  # blank → nil (skip below)
    end
    null_cols.each { |col| attrs[col] = nil if model.column_names.include?(col) }
    # Drop blank fields not explicitly marked NULL — let DB use its default
    attrs.reject! { |col, val| val.nil? && !null_cols.include?(col) }

    model.create!(attrs)
    redirect_back fallback_location: database_table_path(@database, @table),
                  notice: 'Eintrag erstellt.'
  rescue => e
    redirect_back fallback_location: database_table_path(@database, @table),
                  alert: "Fehler: #{e.message.split("\n").first}"
  end

  def update_row
    @database = params[:db]
    @table    = params[:table]
    model     = Database.model_for(@database, @table)
    pk_cols   = Array(model.primary_key)

    pk_vals = params[:pk].to_unsafe_h
    scope   = model.all
    pk_vals.each { |col, val| scope = scope.where(col => val) }
    record = scope.first
    return redirect_back(fallback_location: database_table_path(@database, @table),
                         alert: 'Zeile nicht gefunden.') unless record

    null_cols  = Array(params[:null_cols])
    row_params = params[:row]&.to_unsafe_h || {}

    attrs = model.column_names.each_with_object({}) do |col, h|
      next if pk_cols.include?(col)
      if null_cols.include?(col)
        h[col] = nil
      elsif row_params.key?(col)
        h[col] = row_params[col]
      end
    end

    record.update!(attrs)
    redirect_back fallback_location: database_table_path(@database, @table),
                  notice: 'Zeile gespeichert.'
  rescue => e
    redirect_back fallback_location: database_table_path(@database, @table),
                  alert: "Fehler: #{e.message.split("\n").first}"
  end

  private

  def filtered(model)
    return model if @query.blank?

    like = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
    conn = model.connection
    cols = selected_columns
    conditions = cols.map { |col| "CAST(#{conn.quote_column_name(col)} AS TEXT) ILIKE :q" }
                     .join(' OR ')
    model.where(conditions, q: like)
  end

  def selected_columns
    return @columns if params[:columns].blank?

    Array(params[:columns]).select { |c| @columns.include?(c) }.presence || @columns
  end

  def build_search_params
    {}.tap do |h|
      h[:q]       = @query              if @query.present?
      h[:columns] = params[:columns]    if params[:columns].present?
    end
  end
end
