class DeletedRow < ApplicationRecord
  belongs_to :user

  scope :active,    -> { where(restored_at: nil) }
  scope :restored,  -> { where.not(restored_at: nil) }
  scope :for_table, ->(db, tbl) { where(db_name: db, table_name: tbl) }

  def restored?
    restored_at.present?
  end

  def pk_label
    pk_data.map { |k, v| "#{k} = #{v}" }.join(" · ")
  end
end
