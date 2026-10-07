class AddRenderErrorAndVersionIndex < ActiveRecord::Migration[8.1]
  # Stores safe render diagnostics and enforces per-source version numbering.
  #
  # @return [void]
  def change
    add_column :render_versions, :render_error, :text
    add_index :render_versions, [ :source_asset_id, :version_number ], unique: true
  end
end
