class AddBrowserFieldsToPageVisits < ActiveRecord::Migration[7.0]
  def change
    add_column :page_visits, :tab_id, :integer
    add_column :page_visits, :domain, :string
    add_column :page_visits, :duration_seconds, :integer
    add_column :page_visits, :active_duration_seconds, :integer
    add_column :page_visits, :engagement_rate, :float
    add_column :page_visits, :idle_periods, :jsonb
    add_column :page_visits, :last_heartbeat, :bigint
    add_column :page_visits, :anonymous_client_id, :string
  end
end
