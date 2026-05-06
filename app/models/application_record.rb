class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # Eigener Connection-Pool, getrennt von ActiveRecord::Base.
  # Bleibt unberührt wenn ApplicationController die PG-Verbindung
  # für den Database-Browser auf User-Credentials umschaltet.
  establish_connection Rails.env.to_sym
end
