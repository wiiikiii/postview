class Api::V1::TablesController < Api::BaseController
  # GET /api/v1/databases/:db/tables
  def index
    tables = Database.tables_for(params[:db])
    render json: { database: params[:db], tables: tables }
  end

  # GET /api/v1/databases/:db/tables/:table/rows
  def rows
    model = Database.model_for(params[:db], params[:table])
    q     = params[:q].to_s.strip
    scope = q.present? ? filtered(model, q) : model
    rows  = scope.page(params[:page] || 1).per(params[:per_page] || 25)
    render json: {
      database:    params[:db],
      table:       params[:table],
      page:        rows.current_page,
      total_pages: rows.total_pages,
      total_count: rows.total_count,
      columns:     model.column_names,
      rows:        rows.map { |r| model.column_names.index_with { |c| r.read_attribute(c) } }
    }
  rescue NameError
    render json: { error: "Table not found" }, status: :not_found
  end

  # POST /api/v1/databases/:db/tables/:table/rows
  def create_row
    model     = Database.model_for(params[:db], params[:table])
    body      = json_body
    null_cols = Array(body["null_cols"])
    row_vals  = body["row"] || {}

    attrs = {}
    row_vals.each do |col, val|
      next unless model.column_names.include?(col)
      attrs[col] = val.presence
    end
    null_cols.each { |col| attrs[col] = nil if model.column_names.include?(col) }
    attrs.reject! { |col, val| val.nil? && !null_cols.include?(col) }

    record  = model.create!(attrs)
    pk_cols = Array(model.primary_key)
    render json: { created: true, pk: pk_cols.index_with { |c| record.read_attribute(c) } },
           status: :created
  rescue NameError
    render json: { error: "Table not found" }, status: :not_found
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # PATCH /api/v1/databases/:db/tables/:table/rows
  def update_row
    model    = Database.model_for(params[:db], params[:table])
    body     = json_body
    pk_vals  = body["pk"]
    return render json: { error: "pk required" }, status: :bad_request if pk_vals.blank?

    pk_cols = Array(model.primary_key)
    scope   = model.all
    pk_vals.each { |col, val| scope = scope.where(col => val) }
    record = scope.first
    return render json: { error: "Row not found" }, status: :not_found unless record

    null_cols  = Array(body["null_cols"])
    row_vals   = body["row"] || {}

    attrs = model.column_names.each_with_object({}) do |col, h|
      next if pk_cols.include?(col)
      if null_cols.include?(col)
        h[col] = nil
      elsif row_vals.key?(col)
        h[col] = row_vals[col]
      end
    end

    record.update!(attrs)
    render json: { updated: true }
  rescue NameError
    render json: { error: "Table not found" }, status: :not_found
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # DELETE /api/v1/databases/:db/tables/:table/rows
  def delete_row
    model   = Database.model_for(params[:db], params[:table])
    pk_vals = json_body["pk"] || params[:pk]&.to_unsafe_h
    return render json: { error: "pk required" }, status: :bad_request if pk_vals.blank?

    scope  = model.all
    pk_vals.each { |col, val| scope = scope.where(col => val) }
    record = scope.first
    return render json: { error: "Row not found" }, status: :not_found unless record

    record.destroy!
    render json: { deleted: true }
  rescue NameError
    render json: { error: "Table not found" }, status: :not_found
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # GET /api/v1/databases/:db/tables/:table/structure
  def structure
    model = Database.model_for(params[:db], params[:table])
    pk    = Array(model.primary_key)
    render json: {
      database: params[:db],
      table:    params[:table],
      columns:  model.columns.map { |c|
        { name: c.name, sql_type: c.sql_type, nullable: c.null,
          default: c.default, primary_key: pk.include?(c.name) }
      }
    }
  rescue NameError
    render json: { error: "Table not found" }, status: :not_found
  end

  # GET /api/v1/databases/:db/tables/:table/info
  def info
    mod = Database.connect(params[:db])
    mod::Connect.with_connection do |dc|
      qt    = dc.quote(params[:table])
      stats = dc.execute(<<~SQL).first
        SELECT s.*,
               pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size_pretty,
               pg_size_pretty(pg_relation_size(c.oid))       AS table_size_pretty,
               pg_size_pretty(pg_indexes_size(c.oid))        AS index_size_pretty,
               pg_total_relation_size(c.oid)                 AS total_size_bytes,
               r.rolname                                      AS owner,
               n.nspname                                      AS schema
        FROM   pg_stat_user_tables s
        JOIN   pg_class c ON c.relname = s.relname
               AND c.relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = s.schemaname)
        LEFT JOIN pg_roles     r ON r.oid = c.relowner
        JOIN   pg_namespace    n ON n.oid = c.relnamespace
        WHERE  s.relname = #{qt} LIMIT 1
      SQL
      return render json: { error: "Table not found" }, status: :not_found unless stats

      indexes = dc.execute(<<~SQL).to_a
        SELECT i.relname AS name, ix.indisprimary AS primary,
               ix.indisunique AS unique,
               pg_size_pretty(pg_relation_size(i.oid)) AS size,
               array_to_string(ARRAY(
                 SELECT pg_get_indexdef(ix.indexrelid, k, true)
                 FROM generate_subscripts(ix.indkey, 1) AS k
               ), ', ') AS columns
        FROM   pg_index ix
        JOIN   pg_class c ON c.oid = ix.indrelid
        JOIN   pg_class i ON i.oid = ix.indexrelid
        WHERE  c.relname = #{qt}
        ORDER BY ix.indisprimary DESC, i.relname
      SQL

      render json: { database: params[:db], table: params[:table],
                     stats: stats, indexes: indexes }
    end
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def filtered(model, q)
    like = "%#{ActiveRecord::Base.sanitize_sql_like(q)}%"
    conn = model.connection
    conditions = model.column_names
      .map { |col| "CAST(#{conn.quote_column_name(col)} AS TEXT) ILIKE :q" }
      .join(" OR ")
    model.where(conditions, q: like)
  end

  def json_body
    return {} unless request.content_type&.include?("application/json")
    JSON.parse(request.body.read)
  rescue JSON::ParserError
    {}
  end
end
