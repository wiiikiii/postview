Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  get "/databases/:id/info"             => "main#database_info",    as: :database_info
  get "/databases/:id"                  => "main#database",         as: :database
  get    "/databases/:db/:table/structure"         => "main#structure",   as: :database_table_structure
  get    "/databases/:db/:table/info"             => "main#table_info",  as: :database_table_info
  post   "/databases/:db/:table/rows"             => "main#create_row",  as: :create_table_row
  patch  "/databases/:db/:table/rows"             => "main#update_row",  as: :update_table_row
  delete "/databases/:db/:table/rows"             => "main#delete_row",  as: :delete_table_row
  get    "/databases/:db/:table/trash"            => "main#trash",       as: :database_table_trash
  post   "/databases/:db/:table/trash/:id/restore" => "main#restore_row", as: :restore_table_row
  delete "/databases/:db/:table/trash/:id"        => "main#purge_row",   as: :purge_table_row
  get    "/databases/:db/query"                        => "main#query_console", as: :database_query
  post   "/databases/:db/query"                        => "main#execute_query"
  post   "/databases/:db/query/export"                 => "main#export_query",  as: :export_query
  get    "/databases/:db/query/schema/:table"          => "main#query_schema",  as: :database_query_schema

  get    "/databases/:db/:table"                  => "main#table",       as: :database_table

  get   "/preferences", to: "preferences#show"
  patch "/preferences", to: "preferences#update"

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
      get    "/databases",                               to: "databases#index"
      get    "/databases/:db",                           to: "databases#show",      as: :db
      get    "/databases/:db/tables",                    to: "tables#index",        as: :db_tables
      get    "/databases/:db/tables/:table/rows",        to: "tables#rows",         as: :db_table_rows
      post   "/databases/:db/tables/:table/rows",        to: "tables#create_row"
      patch  "/databases/:db/tables/:table/rows",        to: "tables#update_row"
      delete "/databases/:db/tables/:table/rows",        to: "tables#delete_row"
      get    "/databases/:db/tables/:table/structure",   to: "tables#structure",    as: :db_table_structure
      get    "/databases/:db/tables/:table/info",        to: "tables#info"
    end
  end
end
