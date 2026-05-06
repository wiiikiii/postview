class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :username, null: false
      t.string :email, null: false
      t.string :password_digest
      t.string :pg_username, null: false
      t.text :pg_password, null: false
      t.string :otp_secret
      t.boolean :otp_enabled, default: false, null: false

      t.timestamps
    end

    add_index :users, :username, unique: true
    add_index :users, :email, unique: true
  end
end
