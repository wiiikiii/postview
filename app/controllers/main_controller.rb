class MainController < ApplicationController

  def index
    @databases = Database.all
  end

  def database
    @database = params[ :id ]
    @tables = Database.tables_for( params[ :id ] )
  end

  def table
    @database = params[ :db ]
    @table = params[ :id ]
    puts "--------------------------"
    puts "Database::#{@database.classify}::#{@table.classify}"

    @tables = Database.tables_for( params[ :db ] )
    @rows = "Database::#{@database.classify}::#{@table.classify}".constantize.all
  end

end
