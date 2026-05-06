class Api::V1::DatabasesController < Api::BaseController
  def index
    dbs = Database.where(datistemplate: false).order(:datname)
    render json: { databases: dbs.map { |d| { name: d.datname } } }
  end
end
