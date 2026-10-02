class CreateProducts < ActiveRecord::Migration[8.1]
  def change
    create_table :products do |t|
      t.string :affiliate_provider
      t.string :source_product_id
      t.string :merchant
      t.string :title
      t.text :description
      t.text :images
      t.decimal :price
      t.decimal :original_price
      t.decimal :discount
      t.string :category
      t.decimal :rating
      t.integer :sold
      t.decimal :commission
      t.string :original_product_url
      t.string :affiliate_url
      t.text :raw_source_data
      t.datetime :last_synced_at

      t.timestamps
    end

    add_index :products, [ :affiliate_provider, :source_product_id ], unique: true
  end
end
