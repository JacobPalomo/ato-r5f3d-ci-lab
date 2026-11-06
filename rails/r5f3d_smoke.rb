# This script is run only inside a disposable Chatwoot Rails container in CI.
# It never creates a Chatwoot message or accesses real customer data.
require 'json'

expected_database = 'chatwoot_production'
db = ActiveRecord::Base.connection
actual_database = db.select_value('SELECT current_database()')
abort "WRONG_DATABASE: #{actual_database.inspect}" unless actual_database == expected_database

required_tables = %w[messages conversations accounts]
missing = required_tables.reject { |name| db.data_source_exists?(name) }
abort "MISSING_TABLES: #{missing.join(',')}" unless missing.empty?

indexes = db.indexes('messages')
source_index = indexes.find { |index| index.name == 'index_messages_on_source_id' }
abort 'SOURCE_ID_INDEX_MISSING' unless source_index
abort 'SOURCE_ID_UNEXPECTEDLY_UNIQUE' if source_index.unique

puts JSON.generate({
  phase: 'R5F-3D',
  rails_runtime: true,
  rails_version: Rails.version,
  active_record_database: actual_database,
  required_tables_present: true,
  source_id_unique: source_index.unique,
  delivery_key_guard_installed: false,
  sidekiq_job_executed: false,
  whatsapp_provider_tested: false,
  note: 'Smoke only: no patch, no RSpec, no provider messages'
})
