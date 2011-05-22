class CreateStars < ActiveRecord::Migration
  def self.up
    create_table :stars do |t|
      t.string   :uri
      t.string   :title
      t.string   :color
      t.integer  :star_count,         :default => 0
      t.integer  :request_count,      :default => 0
      t.integer  :api_request_count,  :default => 0
      t.datetime :api_request_at
      t.integer  :static_image_count, :default => 0
      t.integer  :cached_image_count, :default => 0
      t.integer  :create_image_count, :default => 0
      t.integer  :error_count,        :default => 0
      t.text     :error_message
      t.datetime :error_at
      t.timestamps
    end
    add_index :stars, :uri
  end

  def self.down
    drop_table :stars
  end
end
