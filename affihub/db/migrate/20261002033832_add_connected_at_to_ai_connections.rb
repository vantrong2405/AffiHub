class AddConnectedAtToAIConnections < ActiveRecord::Migration[8.1]
  def change
    add_column :ai_connections, :connected_at, :datetime
  end
end
