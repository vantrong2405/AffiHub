# frozen_string_literal: true

class AddUserAndIsMallToProducts < ActiveRecord::Migration[8.1]
  def change
    add_reference :products, :user, null: false, foreign_key: true
    add_column :products, :is_mall, :boolean
  end
end
