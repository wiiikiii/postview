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
    puts "Database::#{Database.object_classify_name(@database)}::#{Database.object_classify_name(@table)}"

    @tables = Database.tables_for( params[ :db ] )
    @rows = "Database::#{Database.object_classify_name(@database)}::#{Database.object_classify_name(@table)}".constantize.all
  end

end
