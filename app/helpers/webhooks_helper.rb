# frozen_string_literal: true
module WebhooksHelper
  GENERIC_SOURCES = [
    ['Any', 'any'],
    ['Any CI', 'any_ci'],
    ['Any code push', 'any_code'],
    ['Any Pull Request', 'any_pull_request']
  ].freeze

  NO_SOURCE = [['None', 'none']].freeze

  def webhook_sources_for_select(sources, none: false)
    default_sources = none ? GENERIC_SOURCES + NO_SOURCE : GENERIC_SOURCES
    default_sources + sources_for_select(sources)
  end

  def sources_for_select(sources)
    sources.map { |source| [source.titleize, source] }.to_a
  end

  def webhook_help_text(source)
    case source
    when 'generic'
      help_text = <<~HTML.html_safe
        Generic endpoint to start deploys, expects payload in the form of:
        <br>
        <pre>
        {
          deploy: {
            branch: &ltname&gt,
            commit: {
              sha: &ltsha&gt,
              message: &ltmessage&gt
            }
          }
        }
        </pre>
      HTML
      additional_info(help_text)
    else
      ''
    end
  end
end
