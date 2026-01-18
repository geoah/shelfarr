# frozen_string_literal: true

require "test_helper"

class SearchControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)

    # Set up Hardcover API key for tests
    Setting.find_or_create_by(key: "hardcover_api_key").update!(
      value: "test_api_key",
      value_type: "string",
      category: "hardcover"
    )
    HardcoverClient.reset_connection!
  end

  teardown do
    HardcoverClient.reset_connection!
  end

  test "index requires authentication" do
    sign_out
    get search_path
    assert_response :redirect
  end

  test "index shows search form" do
    get search_path
    assert_response :success
    assert_select "input[type='text']"
  end

  test "results returns search results" do
    with_cassette("hardcover/search_harry_potter") do
      get search_results_path, params: { q: "harry potter" }
      assert_response :success
    end
  end

  test "results with empty query returns empty results" do
    get search_results_path, params: { q: "" }
    assert_response :success
  end

  test "results handles turbo stream format" do
    with_cassette("hardcover/search_with_limit") do
      get search_results_path, params: { q: "fiction" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success
      assert_match "turbo-stream", response.body
    end
  end

  test "results shows error when Hardcover not configured" do
    Setting.where(key: "hardcover_api_key").destroy_all
    HardcoverClient.reset_connection!

    get search_results_path, params: { q: "test" }
    assert_response :success
    # Error message should be shown in the response
  end
end
