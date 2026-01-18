# frozen_string_literal: true

require "test_helper"

class HardcoverClientTest < ActiveSupport::TestCase
  setup do
    # Set up API key for tests
    Setting.find_or_create_by(key: "hardcover_api_key").update!(
      value: "test_api_key",
      value_type: "string",
      category: "hardcover"
    )
    HardcoverClient.reset_connection!
  end

  teardown do
    Setting.where(key: "hardcover_api_key").destroy_all
    HardcoverClient.reset_connection!
  end

  test "configured? returns false without API key" do
    Setting.where(key: "hardcover_api_key").destroy_all
    refute HardcoverClient.configured?
  end

  test "configured? returns true with API key" do
    assert HardcoverClient.configured?
  end

  test "search raises NotConfiguredError without API key" do
    Setting.where(key: "hardcover_api_key").destroy_all
    HardcoverClient.reset_connection!

    assert_raises HardcoverClient::NotConfiguredError do
      HardcoverClient.search("test")
    end
  end

  test "search returns array of SearchResult" do
    with_cassette("hardcover/search_harry_potter") do
      results = HardcoverClient.search("harry potter")

      assert_kind_of Array, results
      assert results.any?
      assert_kind_of HardcoverClient::SearchResult, results.first

      result = results.first
      assert_equal "328491", result.id
      assert_equal "Harry Potter and the Sorcerer's Stone", result.title
      assert_equal "J.K. Rowling", result.author
      assert_equal 1997, result.year
      assert result.cover_url.present?
      assert result.has_audiobook
      assert result.has_ebook
    end
  end

  test "search returns empty array for no results" do
    with_cassette("hardcover/search_no_results") do
      results = HardcoverClient.search("asdfghjklqwertyuiop123456789")
      assert_equal [], results
    end
  end

  test "search respects limit parameter" do
    with_cassette("hardcover/search_with_limit") do
      results = HardcoverClient.search("fiction", limit: 5)
      assert results.length <= 5
    end
  end

  test "test_connection returns true when configured" do
    with_cassette("hardcover/test_connection") do
      assert HardcoverClient.test_connection
    end
  end

  test "SearchResult has expected attributes" do
    result = HardcoverClient::SearchResult.new(
      id: "123",
      title: "Test Book",
      author: "Test Author",
      year: 2020,
      cover_image_url: "https://example.com/cover.jpg",
      description: "A test book",
      has_audiobook: true,
      has_ebook: false
    )

    assert_equal "123", result.id
    assert_equal "Test Book", result.title
    assert_equal "Test Author", result.author
    assert_equal 2020, result.year
    assert_equal "https://example.com/cover.jpg", result.cover_url
    assert_equal "A test book", result.description
    assert result.has_audiobook
    refute result.has_ebook
  end

  test "cover_url method returns cover_image_url attribute" do
    result = HardcoverClient::SearchResult.new(
      id: "123",
      title: "Test",
      author: nil,
      year: nil,
      cover_image_url: "https://example.com/cover.jpg",
      description: nil,
      has_audiobook: false,
      has_ebook: false
    )

    # Hardcover provides full URLs directly, size parameter is ignored
    assert_equal "https://example.com/cover.jpg", result.cover_url(size: :m)
    assert_equal "https://example.com/cover.jpg", result.cover_url(size: :l)
  end
end
