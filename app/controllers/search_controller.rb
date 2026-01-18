# frozen_string_literal: true

class SearchController < ApplicationController
  def index
    @query = params[:q]
  end

  def results
    @query = params[:q].to_s.strip

    if @query.blank?
      @results = []
      @error = nil
    else
      begin
        @results = HardcoverClient.search(@query)
        @error = nil
      rescue HardcoverClient::NotConfiguredError
        @results = []
        @error = "Hardcover API is not configured. Please add your API key in Settings."
      rescue HardcoverClient::ConnectionError => e
        @results = []
        @error = "Unable to connect to Hardcover. Please try again later."
        Rails.logger.error("Hardcover connection error: #{e.message}")
      rescue HardcoverClient::Error => e
        @results = []
        @error = "Search failed. Please try again."
        Rails.logger.error("Hardcover error: #{e.message}")
      end
    end

    respond_to do |format|
      format.turbo_stream
      format.html { render :index }
    end
  end
end
