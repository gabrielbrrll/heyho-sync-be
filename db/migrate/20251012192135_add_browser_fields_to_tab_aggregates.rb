class AddBrowserFieldsToTabAggregates < ActiveRecord::Migration[7.0]
  def change
    add_column :tab_aggregates, :domain_durations, :jsonb
    add_column :tab_aggregates, :page_count, :bigint
    add_column :tab_aggregates, :current_url, :string
    add_column :tab_aggregates, :current_domain, :string
    add_column :tab_aggregates, :statistics, :jsonb
  end
end
