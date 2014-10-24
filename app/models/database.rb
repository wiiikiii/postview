class Database < ActiveRecord::Base
  
  self.table_name = "pg_database"
  self.primary_key = "datdba"
  
  # helper to check if a class exists
	def self.class_exists?(class_name)
	  eval("defined?(#{class_name}) && #{class_name}.is_a?(Class)") == true
	end

  # helper for createing a class
	def self.create_class(class_name, superclass, &block)
    klass = Class.new superclass, &block
    Object.const_set class_name, klass
  end

	#
	# Create a local table model
	#
	def self.alloc_local_table( tablename )
		puts "Create local model for #{tablename}"
		create_class( tablename.classify, ActiveRecord::Base ) do
			def self.table_name_prefix; 'trans_'; end
			def self.attributes_protected_by_default; []; end
		end if not class_exists?( tablename.classify )
	end
  
  def self.tables_for( database )
    if not Database.const_defined?( database.classify )
      Database.module_eval <<-"EOS"
        module #{database.classify}
          class Connect < ActiveRecord::Base
            self.table_name = "pg_database"
            self.primary_key = "datdba"
            def self.db_config
              config = ActiveRecord::Base.connection.instance_eval { @config }
              config.merge( :database => '#{database}', :pool => 1 )
            end
            establish_connection( db_config )
          end
          # self
        end
      EOS
    end
    
    #
    # establish connection to be able to get all tables
    #
    db = "Database::#{database.classify}".constantize
    conn = "Database::#{database.classify}::Connect".constantize.connection
    begin
      conn.tables.each do | table |
        if not db.const_defined?( "Database::#{database.classify}::#{table.classify}" )
          puts "* create table Database::#{database.classify}::#{table.classify}"
          #
          # we have created a Module Database::DBNAME in which we will
          # create all classes of all tables we find in database
          #
          "Database::#{database.classify}".constantize.module_eval <<-"EOS"
            class #{table.classify} < #{"Database::#{database.classify}::Connect".constantize}
              self.table_name = "#{table.to_sym}"
              self.primary_key = :id
              #establish_connection( db_config )
              #connection
            end
          EOS
        end
      end
    rescue Exception => e
      puts e
    end
    "Database::#{database.classify}".constantize.constants
  end
  
end

