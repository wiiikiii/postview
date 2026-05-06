Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  get "/databases/:id"        => "main#database",  as: :database
  get "/databases/:db/:table" => "main#table",     as: :database_table

  root "main#index"
end
