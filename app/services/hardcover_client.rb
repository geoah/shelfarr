# frozen_string_literal: true

# Client for interacting with the Hardcover GraphQL API
# https://docs.hardcover.app/api/getting-started/
class HardcoverClient
  GRAPHQL_URL = "https://api.hardcover.app/v1/graphql"

  # Custom error classes
  class Error < StandardError; end
  class ConnectionError < Error; end
  class AuthenticationError < Error; end
  class NotConfiguredError < Error; end
  class RateLimitError < Error; end

  # Data structure for search results
  SearchResult = Data.define(:id, :title, :author, :year, :cover_url, :description, :has_audiobook, :has_ebook) do
    # For compatibility with views that might call cover_url as a method
    def cover_url(size: nil)
      # Hardcover provides full URLs directly, size parameter ignored
      self[:cover_url]
    end
  end

  class << self
    # Search for books by query
    # Returns array of SearchResult
    def search(query, limit: nil)
      ensure_configured!

      limit ||= SettingsService.get("hardcover_search_limit", default: 20)

      graphql_query = <<~GRAPHQL
        query SearchBooks($query: String!, $perPage: Int!) {
          search(query: $query, query_type: Book, per_page: $perPage) {
            results
          }
        }
      GRAPHQL

      variables = { query: query, perPage: limit }
      response = execute_query(graphql_query, variables)

      parse_search_results(response)
    end

    # Get book details by ID
    # Returns SearchResult or nil
    def book(book_id)
      ensure_configured!

      graphql_query = <<~GRAPHQL
        query GetBook($id: Int!) {
          books(where: {id: {_eq: $id}}, limit: 1) {
            id
            title
            release_year
            description
            image { url }
            contributions { author { name } }
          }
        }
      GRAPHQL

      variables = { id: book_id.to_i }
      response = execute_query(graphql_query, variables)

      books = response.dig("data", "books") || []
      return nil if books.empty?

      parse_book(books.first)
    end

    # Check if Hardcover is configured (has API key)
    def configured?
      SettingsService.hardcover_configured?
    end

    # Test connection to Hardcover
    def test_connection
      ensure_configured!

      # Simple query to verify connection
      graphql_query = <<~GRAPHQL
        query TestConnection {
          search(query: "test", query_type: Book, per_page: 1) {
            results
          }
        }
      GRAPHQL

      execute_query(graphql_query, {})
      true
    rescue Error
      false
    end

    # Reset cached connection (for tests)
    def reset_connection!
      @connection = nil
    end

    private

    def ensure_configured!
      raise NotConfiguredError, "Hardcover API is not configured" unless configured?
    end

    def execute_query(query, variables)
      response = connection.post do |req|
        req.body = { query: query, variables: variables }.to_json
      end

      handle_response(response)
    rescue Faraday::ConnectionFailed, Faraday::TimeoutError, Faraday::SSLError => e
      raise ConnectionError, "Failed to connect to Hardcover: #{e.message}"
    end

    def connection
      @connection ||= Faraday.new(url: GRAPHQL_URL) do |f|
        f.request :json
        f.response :json, parser_options: { symbolize_names: false }
        f.adapter Faraday.default_adapter
        f.headers["Authorization"] = "Bearer #{api_key}"
        f.headers["Content-Type"] = "application/json"
        f.options.timeout = 30
        f.options.open_timeout = 10
      end
    end

    def api_key
      SettingsService.get(:hardcover_api_key)
    end

    def handle_response(response)
      case response.status
      when 200
        body = response.body

        # Check for GraphQL errors
        if body["errors"].present?
          error_message = body["errors"].map { |e| e["message"] }.join(", ")

          if error_message.include?("unauthorized") || error_message.include?("authentication")
            raise AuthenticationError, "Invalid Hardcover API key"
          end

          raise Error, "Hardcover API error: #{error_message}"
        end

        body
      when 401, 403
        raise AuthenticationError, "Invalid Hardcover API key"
      when 429
        raise RateLimitError, "Hardcover rate limit exceeded (60 requests/minute)"
      else
        raise Error, "Hardcover API error: #{response.status}"
      end
    end

    def parse_search_results(response)
      results = response.dig("data", "search", "results", "hits") || []

      results.map do |hit|
        doc = hit["document"]
        next unless doc

        SearchResult.new(
          id: doc["id"].to_s,
          title: doc["title"],
          author: Array(doc["author_names"]).first,
          year: doc["release_year"],
          cover_url: doc.dig("image", "url"),
          description: doc["description"],
          has_audiobook: doc["has_audiobook"] || false,
          has_ebook: doc["has_ebook"] || false
        )
      end.compact
    end

    def parse_book(book_data)
      # Extract first author from contributions
      author = book_data.dig("contributions", 0, "author", "name")

      SearchResult.new(
        id: book_data["id"].to_s,
        title: book_data["title"],
        author: author,
        year: book_data["release_year"],
        cover_url: book_data.dig("image", "url"),
        description: book_data["description"],
        has_audiobook: false,  # Not available in direct book query
        has_ebook: false
      )
    end
  end
end
