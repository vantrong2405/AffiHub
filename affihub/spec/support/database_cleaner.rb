# frozen_string_literal: true

require "database_cleaner/active_record"

RSpec.configure do |config|
  config.use_transactional_fixtures = false

  config.before(:suite) do
    DatabaseCleaner.clean_with(:truncation)
  end

  config.before(:each) do |example|
    default_strategy = example.metadata[:type] == :system ? :truncation : :transaction
    DatabaseCleaner.strategy = example.metadata.fetch(:database_cleaner, default_strategy)
    DatabaseCleaner.start
  end

  config.append_after(:each) do
    DatabaseCleaner.clean
  end
end
