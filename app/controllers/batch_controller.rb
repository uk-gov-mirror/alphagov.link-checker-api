class BatchController < ApplicationController
  class CreateParams
    include ActiveModel::Validations

    attr_accessor :uris, :checked_within, :webhook_uri

    validates :uris, presence: true
    validates :checked_within, numericality: { greater_than: 0 }

    def initialize(params)
      @params = params
      @uris = permitted_params[:uris]
      @checked_within = (permitted_params[:checked_within] || 24.hours).to_i
      @webhook_uri = permitted_params[:webhook_uri]
    end

    def permitted_params
      @permitted_params ||= @params.permit(:checked_within, :webhook_uri, uris: [])
    end
  end

  def create
    create_params = CreateParams.new(params)
    create_params.validate!

    batch = ActiveRecord::Base.transaction do
      links = Link.fetch_all(create_params.uris)
      checks = Check.fetch_all(links, within: create_params.checked_within)
      Batch.create!(checks: checks, webhook_uri: create_params.webhook_uri)
    end

    if batch.completed?
      WebhookJob.perform_later(batch_report(batch), batch.webhook_uri) if batch.webhook_uri
      render(json: batch_report(batch), status: 201)
    else
      batch.checks.each do |check|
        CheckJob.perform_later(check)
      end

      render(json: batch_report(batch), status: 202)
    end
  end

  def show
    batch = Batch.find(params[:id])
    render(json: batch_report(batch))
  end

private

  def batch_report(batch)
    BatchPresenter.new(batch).report
  end
end
