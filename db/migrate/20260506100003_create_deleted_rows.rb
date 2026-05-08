class CreateDeletedRows < ActiveRecord::Migration[8.1]
  def change
    create_table :deleted_rows do |t|
      t.references :user, null: false, foreign_key: true
      t.string  :db_name,    null: false
      t.string  :table_name, null: false
      t.jsonb   :pk_data,    null: false, default: {}
      t.jsonb   :row_data,   null: false, default: {}
      t.datetime :restored_at

      t.timestamps
    end

    add_index :deleted_rows, [:db_name, :table_name]
  end
end
