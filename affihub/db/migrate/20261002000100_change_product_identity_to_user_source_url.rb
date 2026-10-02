# frozen_string_literal: true

class ChangeProductIdentityToUserSourceUrl < ActiveRecord::Migration[8.1]
  def change
    remove_index :products, name: "index_products_on_affiliate_provider_and_source_product_id"
    add_index :products, %i[user_id affiliate_provider original_product_url],
              unique: true,
              name: "index_products_on_user_provider_and_original_url"
  end
end
