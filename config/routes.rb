Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  get "/databases/:id/info"             => "main#database_info",    as: :database_info
  get "/databases/:id"                  => "main#database",         as: :database
  get   "/databases/:db/:table/structure" => "main#structure",    as: :database_table_structure
  get   "/databases/:db/:table/info"     => "main#table_info",  as: :database_table_info
  post  "/databases/:db/:table/rows"     => "main#create_row",  as: :create_table_row
  patch "/databases/:db/:table/rows"     => "main#update_row",  as: :update_table_row
  get   "/databases/:db/:table"          => "main#table",       as: :database_table

  root "main#index"

  # Auth
  get    "/login",  to: "sessions#new",     as: :login
  post   "/login",  to: "sessions#create"
  delete "/logout", to: "sessions#destroy",  as: :logout

  # 2FA during login
  get  "/two_factor/verify", to: "two_factor#show",   as: :two_factor_verify
  post "/two_factor/verify", to: "two_factor#create"

  # Magic links
  get  "/magic_link",         to: "magic_links#new",    as: :new_magic_link
  post "/magic_link",         to: "magic_links#create",  as: :magic_link
  get  "/magic_link/:token",  to: "magic_links#show",   as: :magic_link_verify

  # Profile & 2FA setup
  get    "/profile",                   to: "profiles#show",            as: :profile
  patch  "/profile",                   to: "profiles#update"
  get    "/profile/two_factor/setup",  to: "two_factor_setups#new",    as: :new_two_factor_setup
  post   "/profile/two_factor/setup",  to: "two_factor_setups#create", as: :two_factor_setups
  delete "/profile/two_factor",        to: "two_factor_setups#destroy", as: :disable_two_factor

  # API tokens
  resources :api_tokens, only: %i[index create destroy], path: "/profile/api_tokens"

  # API
  namespace :api do
    get "/docs", to: "docs#show", as: :docs
    namespace :v1 do
      get "/databases",                             to: "databases#index"
      get "/databases/:db/tables",                  to: "tables#index",     as: :db_tables
      get "/databases/:db/tables/:table/rows",      to: "tables#rows",      as: :db_table_rows
      get "/databases/:db/tables/:table/structure", to: "tables#structure", as: :db_table_structure
    end
  end
end
