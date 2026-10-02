class AddCodexFieldsToAIConnections < ActiveRecord::Migration[8.1]
  def change
    add_column :ai_connections, :id_token, :string
    add_column :ai_connections, :chatgpt_account_id, :string
    add_column :ai_connections, :chatgpt_plan_type, :string
  end
end
