# frozen_string_literal: true

require "vcr"
require "webmock/minitest"

VCR.configure do |config|
  config.cassette_library_dir = "test/cassettes"
  config.hook_into :webmock
  config.ignore_localhost = true

  # Allow real HTTP connections when recording new cassettes
  config.allow_http_connections_when_no_cassette = false

  # Re-record cassettes every 30 days to keep data fresh
  config.default_cassette_options = {
    record: :new_episodes,
    re_record_interval: 30.days
  }

  # For GraphQL requests (Hardcover), match by URI and method only
  # This avoids issues with whitespace differences in GraphQL query strings
  config.register_request_matcher :graphql_uri do |request_1, request_2|
    request_1.uri == request_2.uri
  end

  # Filter sensitive data
  config.filter_sensitive_data("<PROWLARR_API_KEY>") { ENV["PROWLARR_API_KEY"] }
  config.filter_sensitive_data("<DOWNLOAD_CLIENT_PASSWORD>") { ENV["DOWNLOAD_CLIENT_PASSWORD"] }
  config.filter_sensitive_data("<HARDCOVER_API_KEY>") { ENV["HARDCOVER_API_KEY"] }

  # Filter Hardcover API key from request headers
  config.before_record do |interaction|
    if interaction.request.headers["Authorization"]
      interaction.request.headers["Authorization"] = ["Bearer <HARDCOVER_API_KEY>"]
    end
  end
end

# Helper module for using VCR in tests
module VCRHelper
  def with_cassette(name, options = {}, &block)
    # For hardcover cassettes, use URI-only matching to handle GraphQL body differences
    if name.to_s.start_with?("hardcover/")
      options = { match_requests_on: [:method, :graphql_uri] }.merge(options)
    end
    VCR.use_cassette(name, options, &block)
  end
end
