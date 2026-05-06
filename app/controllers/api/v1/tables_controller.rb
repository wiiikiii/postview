class Api::V1::TablesController < Api::BaseController
  def index
    tables = Database.tables_for(params[:db])
    render json: { database: params[:db], tables: tables }
  end

  def rows
    model = Database.model_for(params[:db], params[:table])
    q = params[:q].to_s.strip
    scope = q.present? ? filtered(model, q) : model
    rows = scope.page(params[:page] || 1).per(params[:per_page] || 25)
    render json: {
      database: params[:db],
      table: params[:table],
      page: rows.current_page,
      total_pages: rows.total_pages,
      total_count: rows.total_count,
      columns: model.column_names,
      rows: rows.map { |r| model.column_names.index_with { |c| r.read_attribute(c) } }
    }
  rescue NameError
    render json: { error: "Table not found" }, status: :not_found
  end

  def structure
    model = Database.model_for(params[:db], params[:table])
    pk = Array(model.primary_key)
    render json: {
      database: params[:db],
      table: params[:table],
      columns: model.columns.map { |c|
        {
          name: c.name,
          sql_type: c.sql_type,
          nullable: c.null,
          default: c.default,
          primary_key: pk.include?(c.name)
        }
      }
    }
  rescue NameError
    render json: { error: "Table not found" }, status: :not_found
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
end
