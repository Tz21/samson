# frozen_string_literal: true
require 'dogapi'
require 'digest/md5'

class DatadogNotification
  def initialize(deploy)
    @deploy = deploy
    @stage = @deploy.stage
  end

  def deliver(additional_tags: [], now: false)
    Rails.logger.info "Sending Datadog notification..."

    status =
      if @deploy.active?
        "info"
      elsif @deploy.succeeded?
        "success"
      else
        "error"
      end

    event = Dogapi::Event.new(
      body,
      msg_title: @deploy.summary,
      event_type: "deploy",
      event_object: Digest::MD5.hexdigest("#{Time.new}|#{rand}"),
      alert_type: status,
      source_type_name: "samson",
      date_happened: now ? Time.now : @deploy.updated_at,
      tags: @stage.datadog_tags_as_array + ["deploy", *additional_tags]
    )

    client = Dogapi::Client.new(api_key, nil, "")
    status = client.emit_event(event)[0]

    if status == "202"
      Rails.logger.info "Sent Datadog notification"
    else
      Rails.logger.info "Failed to send Datadog notification: #{status}"
    end
  end

  private

  def body
    "#{@deploy.user.email} deployed #{@deploy.short_reference} to #{@stage.name}"
  end

  def api_key
    ENV["DATADOG_API_KEY"]
  end
end
