class CreateQuestions < ActiveRecord::Migration
  def self.up
    create_table :questions do |t|
      t.integer :archive_faq_id
      t.string :question
      t.text :answer
      t.string :anchor

      t.timestamps
    end
  end

  def self.down
    drop_table :questions
  end
end
