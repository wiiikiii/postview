class Api::V1::DatabasesController < Api::BaseController

  def index
    dbs = Database.where(datistemplate: false).order(:datname)
    render json: { databases: dbs.map { |d| { name: d.datname } } }
  end

  def show
    c = ActiveRecord::Base.connection
    q = c.quote(params[:db])

    info = c.execute(<<~SQL).first
      SELECT d.datname,
             d.oid::text                                     AS oid,
             r.rolname                                        AS owner,
             pg_encoding_to_char(d.encoding)                 AS encoding,
             d.datcollate, d.datctype,
             t.spcname                                        AS tablespace,
             pg_size_pretty(pg_database_size(d.datname))     AS size_pretty,
             pg_database_size(d.datname)                     AS size_bytes
      FROM   pg_database d
      LEFT JOIN pg_roles      r ON r.oid = d.datdba
      LEFT JOIN pg_tablespace t ON t.oid = d.dattablespace
      WHERE  d.datname = #{q}
    SQL
    return render json: { error: "Database not found" }, status: :not_found unless info

    stats = c.execute("SELECT * FROM pg_stat_database WHERE datname = #{q}").first

    render json: { info: info, stats: stats }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
