class CreateQuestions < ActiveRecord::Migration
  def self.up
    create_table :questions do |t|
      t.integer :archive_faq_id
      t.string :question
      t.text :content
      t.string :anchor
      t.text :screencast
      t.timestamps
    end
    add_column :questions, :content_sanitizer_version, :integer, :default => 0, :null => false, :limit => 2
    add_column :questions, :screencast_sanitizer_version, :integer, :default => 0, :null => false, :limit => 2
    #remove_column :archive_faqs, :content_sanitizer_version
    #remove_column :archive_faqs, :content
  end

  def self.down
    drop_table :questions
  end
end
