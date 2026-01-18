# frozen_string_literal: true

require "test_helper"

class DuplicateDetectionServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "allows request for new book" do
    result = DuplicateDetectionService.check(
      work_id: "12345",
      book_type: "audiobook"
    )

    assert result.allow?
    assert_nil result.message
    assert_nil result.existing_book
  end

  test "blocks request for same book+type already acquired" do
    book = Book.create!(
      title: "Existing Book",
      book_type: :audiobook,
      open_library_work_id: "111111",
      file_path: "/audiobooks/Author/Book"
    )

    result = DuplicateDetectionService.check(
      work_id: "111111",
      book_type: "audiobook"
    )

    assert result.block?
    assert_includes result.message, "already in your library"
    assert_equal book, result.existing_book
  end

  test "blocks request when active request exists" do
    book = Book.create!(
      title: "Pending Book",
      book_type: :audiobook,
      open_library_work_id: "222222"
    )

    request = Request.create!(
      book: book,
      user: @user,
      status: :pending
    )

    result = DuplicateDetectionService.check(
      work_id: "222222",
      book_type: "audiobook"
    )

    assert result.block?
    assert_includes result.message, "active request"
    assert_equal book, result.existing_book
    assert_equal request, result.existing_request
  end

  test "warns when same book exists as different type" do
    Book.create!(
      title: "Has Audiobook",
      book_type: :audiobook,
      open_library_work_id: "333333",
      file_path: "/audiobooks/Author/Book"
    )

    result = DuplicateDetectionService.check(
      work_id: "333333",
      book_type: "ebook"
    )

    assert result.warn?
    assert_includes result.message, "exists as an audiobook"
  end

  test "warns when previous request failed" do
    book = Book.create!(
      title: "Failed Book",
      book_type: :ebook,
      open_library_work_id: "444444"
    )

    Request.create!(
      book: book,
      user: @user,
      status: :failed
    )

    result = DuplicateDetectionService.check(
      work_id: "444444",
      book_type: "ebook"
    )

    assert result.warn?
    assert_includes result.message, "failed"
  end

  test "warns when previous request was not found" do
    book = Book.create!(
      title: "Not Found Book",
      book_type: :audiobook,
      open_library_work_id: "555555"
    )

    Request.create!(
      book: book,
      user: @user,
      status: :not_found
    )

    result = DuplicateDetectionService.check(
      work_id: "555555",
      book_type: "audiobook"
    )

    assert result.warn?
    assert_includes result.message, "not found"
  end

  test "can_request? returns true for allowed" do
    assert DuplicateDetectionService.can_request?(
      work_id: "666666",
      book_type: "audiobook"
    )
  end

  test "can_request? returns true for warned" do
    Book.create!(
      title: "Audiobook Only",
      book_type: :audiobook,
      open_library_work_id: "777777",
      file_path: "/audiobooks/Author/Book"
    )

    assert DuplicateDetectionService.can_request?(
      work_id: "777777",
      book_type: "ebook"
    )
  end

  test "can_request? returns false for blocked" do
    Book.create!(
      title: "Acquired",
      book_type: :ebook,
      open_library_work_id: "888888",
      file_path: "/ebooks/Book.epub"
    )

    refute DuplicateDetectionService.can_request?(
      work_id: "888888",
      book_type: "ebook"
    )
  end
end
