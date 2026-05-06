class MainController < ApplicationController
  def index
    @databases = Database.all.order(:datname)
  end

  def database
    @database = params[:id]
    @tables   = Database.tables_for(@database)
  end

  def table
    @database = params[:db]
    @table    = params[:table]
    @tables   = Database.tables_for(@database)

    model = Database.model_for(@database, @table)
    @columns = model.column_names rescue []
    @rows    = model.page(params[:page]).per(25)
  rescue NameError
    redirect_to database_path(@database), alert: "Table not found."
  end
end
