class FaqRework < ActiveRecord::Migration
  def self.up
    add_column :archive_faqs, :question, :string
    add_column :archive_faqs, :anchor, :string

  end

  def self.down
    remove_column :archive_faqs, :question
    remove_column :archive_faqs, :anchor
  end
end
