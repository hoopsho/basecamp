# frozen_string_literal: true

module ApplicationHelper
  include Pagy::Frontend
  include SeoHelper

  # Inline SVG heroicon helper — Heroicons v2 outline
  # Usage: heroicon('check-circle', variant: :outline, class: 'w-5 h-5')
  def heroicon(name, variant: :outline, **options) # rubocop:disable Metrics/MethodLength
    icons = heroicon_paths
    paths = icons[name]

    unless paths
      Rails.logger.warn("Heroicon '#{name}' not found")
      return ''.html_safe
    end

    css_class = options.delete(:class)

    raw(
      %(<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" ) +
      %(stroke-width="1.5" stroke="currentColor") +
      (css_class ? %( class="#{css_class}") : '') +
      %(>#{paths}</svg>)
    )
  end

  # Task status badge with color coding
  def status_badge(status)
    classes = case status.to_s
    when 'pending'
                'bg-gray-100 dark:bg-gray-700 text-gray-800 dark:text-gray-200'
    when 'in_progress'
                'bg-blue-100 dark:bg-blue-900/30 text-blue-800 dark:text-blue-200'
    when 'waiting_on_human'
                'bg-yellow-100 dark:bg-yellow-900/30 text-yellow-800 dark:text-yellow-200'
    when 'waiting_on_timer'
                'bg-purple-100 dark:bg-purple-900/30 text-purple-800 dark:text-purple-200'
    when 'completed'
                'bg-green-100 dark:bg-green-900/30 text-green-800 dark:text-green-200'
    when 'failed'
                'bg-red-100 dark:bg-red-900/30 text-red-800 dark:text-red-200'
    when 'escalated'
                'bg-orange-100 dark:bg-orange-900/30 text-orange-800 dark:text-orange-200'
    else
                'bg-gray-100 dark:bg-gray-700 text-gray-800 dark:text-gray-200'
    end

    label = status.to_s.humanize

    content_tag :span, label, class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{classes}"
  end

  # Priority indicator with color coding
  def priority_indicator(priority)
    return 'Normal' if priority.nil? || priority == 0

    if priority > 5
      content_tag :span, "High (#{priority})", class: 'text-red-600 dark:text-red-400 font-medium'
    elsif priority < 0
      content_tag :span, "Low (#{priority})", class: 'text-gray-500 dark:text-gray-400'
    else
      content_tag :span, priority, class: 'text-gray-600 dark:text-gray-400'
    end
  end

  # Calculate human-readable task duration
  def task_duration(task)
    return '—' unless task.started_at

    end_time = task.completed_at || Time.current
    duration = end_time - task.started_at

    if duration < 60
      "#{duration.round}s"
    elsif duration < 3600
      "#{(duration / 60).round}m"
    else
      "#{(duration / 3600).round(1)}h"
    end
  end

  # Generate Slack thread URL
  def slack_thread_url(task)
    return '#' unless task.slack_thread_ts.present? && task.agent&.slack_channel.present?

    "https://slack.com/app_redirect?channel=#{task.agent.slack_channel}&thread_ts=#{task.slack_thread_ts}"
  end

  # Event timeline icon name based on event type
  def event_icon_name(event_type)
    case event_type.to_s
    when 'step_started' then 'play'
    when 'step_completed' then 'check-circle'
    when 'step_failed' then 'x-circle'
    when 'llm_call' then 'sparkles'
    when 'llm_escalated' then 'arrow-trending-up'
    when 'human_requested' then 'user'
    when 'human_responded' then 'chat-bubble-left-ellipsis'
    when 'api_called' then 'cloud'
    when 'error' then 'exclamation-triangle'
    when 'note' then 'document-text'
    else 'circle'
    end
  end

  # Event timeline icon background color
  def event_icon_background(event_type)
    case event_type.to_s
    when 'step_started' then 'bg-blue-100 dark:bg-blue-900/30'
    when 'step_completed' then 'bg-green-100 dark:bg-green-900/30'
    when 'step_failed', 'error' then 'bg-red-100 dark:bg-red-900/30'
    when 'llm_call', 'llm_escalated' then 'bg-purple-100 dark:bg-purple-900/30'
    when 'human_requested', 'human_responded' then 'bg-yellow-100 dark:bg-yellow-900/30'
    when 'api_called' then 'bg-gray-100 dark:bg-gray-700'
    else 'bg-gray-100 dark:bg-gray-700'
    end
  end

  # Event timeline icon color
  def event_icon_color(event_type)
    case event_type.to_s
    when 'step_started' then 'text-blue-600 dark:text-blue-400'
    when 'step_completed' then 'text-green-600 dark:text-green-400'
    when 'step_failed', 'error' then 'text-red-600 dark:text-red-400'
    when 'llm_call', 'llm_escalated' then 'text-purple-600 dark:text-purple-400'
    when 'human_requested', 'human_responded' then 'text-yellow-600 dark:text-yellow-400'
    when 'api_called' then 'text-gray-600 dark:text-gray-400'
    else 'text-gray-600 dark:text-gray-400'
    end
  end

  # Human-readable event type label
  def event_type_label(event_type)
    event_type.to_s.humanize
  end

  # LLM tier badge CSS classes
  def llm_tier_badge_classes(tier)
    case tier
    when 1 then 'bg-gray-100 dark:bg-gray-700 text-gray-800 dark:text-gray-200'
    when 2 then 'bg-blue-100 dark:bg-blue-900/30 text-blue-800 dark:text-blue-200'
    when 3 then 'bg-purple-100 dark:bg-purple-900/30 text-purple-800 dark:text-purple-200'
    else 'bg-gray-100 dark:bg-gray-700 text-gray-800 dark:text-gray-200'
    end
  end

  # Confidence score bar color
  def confidence_color(score)
    if score >= 0.8
      'bg-green-500'
    elsif score >= 0.6
      'bg-yellow-500'
    else
      'bg-red-500'
    end
  end

  # Estimate LLM cost from token usage
  def llm_cost_estimate(event)
    return nil unless event.llm_tokens_in && event.llm_tokens_out && event.llm_tier_used

    # Rough estimates per tier
    cost_per_1k = case event.llm_tier_used
    when 1 then 0.001  # Haiku ~$0.001 per 1K tokens
    when 2 then 0.01   # Sonnet ~$0.01 per 1K tokens
    when 3 then 0.10   # Opus ~$0.10 per 1K tokens
    else 0
    end

    total_tokens = event.llm_tokens_in + event.llm_tokens_out
    cost = (total_tokens / 1000.0) * cost_per_1k
    cost < 0.001 ? '<0.001' : cost.round(3).to_s
  end

  # Format JSON data for display
  def format_json(data)
    return data if data.is_a?(String)

    JSON.pretty_generate(data)
  rescue JSON::GeneratorError
    data.to_s
  end

  private

  # Heroicons v2 outline SVG path data
  def heroicon_paths # rubocop:disable Metrics/MethodLength
    {
      'arrow-path' => '<path stroke-linecap="round" stroke-linejoin="round" d="M16.0228 9.34841H21.0154V9.34663M2.98413 19.6444V14.6517M2.98413 14.6517L7.97677 14.6517M2.98413 14.6517L6.16502 17.8347C7.15555 18.8271 8.41261 19.58 9.86436 19.969C14.2654 21.1483 18.7892 18.5364 19.9685 14.1353M4.03073 9.86484C5.21 5.46374 9.73377 2.85194 14.1349 4.03121C15.5866 4.4202 16.8437 5.17312 17.8342 6.1655L21.0154 9.34663M21.0154 4.3558V9.34663" />',
      'x-circle' => '<path stroke-linecap="round" stroke-linejoin="round" d="M9.75 9.75L14.25 14.25M14.25 9.75L9.75 14.25M21 12C21 16.9706 16.9706 21 12 21C7.02944 21 3 16.9706 3 12C3 7.02944 7.02944 3 12 3C16.9706 3 21 7.02944 21 12Z" />',
      'eye' => '<path stroke-linecap="round" stroke-linejoin="round" d="M2.03555 12.3224C1.96647 12.1151 1.9664 11.8907 2.03536 11.6834C3.42372 7.50972 7.36079 4.5 12.0008 4.5C16.6387 4.5 20.5742 7.50692 21.9643 11.6776C22.0334 11.8849 22.0335 12.1093 21.9645 12.3166C20.5761 16.4903 16.6391 19.5 11.9991 19.5C7.36119 19.5 3.42564 16.4931 2.03555 12.3224Z" /><path stroke-linecap="round" stroke-linejoin="round" d="M15 12C15 13.6569 13.6569 15 12 15C10.3431 15 9 13.6569 9 12C9 10.3431 10.3431 9 12 9C13.6569 9 15 10.3431 15 12Z" />',
      'clock' => '<path stroke-linecap="round" stroke-linejoin="round" d="M12 6V12H16.5M21 12C21 16.9706 16.9706 21 12 21C7.02944 21 3 16.9706 3 12C3 7.02944 7.02944 3 12 3C16.9706 3 21 7.02944 21 12Z" />',
      'check-circle' => '<path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75L11.25 15L15 9.75M21 12C21 16.9706 16.9706 21 12 21C7.02944 21 3 16.9706 3 12C3 7.02944 7.02944 3 12 3C16.9706 3 21 7.02944 21 12Z" />',
      'exclamation-triangle' => '<path stroke-linecap="round" stroke-linejoin="round" d="M11.9998 9.00006V12.7501M2.69653 16.1257C1.83114 17.6257 2.91371 19.5001 4.64544 19.5001H19.3541C21.0858 19.5001 22.1684 17.6257 21.303 16.1257L13.9487 3.37819C13.0828 1.87736 10.9167 1.87736 10.0509 3.37819L2.69653 16.1257ZM11.9998 15.7501H12.0073V15.7576H11.9998V15.7501Z" />',
      'code-bracket' => '<path stroke-linecap="round" stroke-linejoin="round" d="M17.25 6.75L22.5 12L17.25 17.25M6.75 17.25L1.5 12L6.75 6.75M14.25 3.75L9.75 20.25" />',
      'chat-bubble-left' => '<path stroke-linecap="round" stroke-linejoin="round" d="M2.25 12.7593C2.25 14.3604 3.37341 15.754 4.95746 15.987C6.04357 16.1467 7.14151 16.27 8.25 16.3556V21L12.326 16.924C12.6017 16.6483 12.9738 16.4919 13.3635 16.481C15.2869 16.4274 17.1821 16.2606 19.0425 15.9871C20.6266 15.7542 21.75 14.3606 21.75 12.7595V6.74056C21.75 5.13946 20.6266 3.74583 19.0425 3.51293C16.744 3.17501 14.3926 3 12.0003 3C9.60776 3 7.25612 3.17504 4.95747 3.51302C3.37342 3.74593 2.25 5.13956 2.25 6.74064V12.7593Z" />',
      'chat-bubble-left-right' => '<path stroke-linecap="round" stroke-linejoin="round" d="M20.25 8.51104C21.1341 8.79549 21.75 9.6392 21.75 10.6082V14.8938C21.75 16.0304 20.9026 16.9943 19.7697 17.0867C19.4308 17.1144 19.0909 17.1386 18.75 17.1592V20.25L15.75 17.25C14.3963 17.25 13.0556 17.1948 11.7302 17.0866C11.4319 17.0623 11.1534 16.9775 10.9049 16.8451M20.25 8.51104C20.0986 8.46232 19.9393 8.43 19.7739 8.41628C18.4472 8.30616 17.1051 8.25 15.75 8.25C14.3948 8.25 13.0528 8.30616 11.7261 8.41627C10.595 8.51015 9.75 9.47323 9.75 10.6082V14.8937C9.75 15.731 10.2099 16.4746 10.9049 16.8451M20.25 8.51104V6.63731C20.25 5.01589 19.0983 3.61065 17.4903 3.40191C15.4478 3.13676 13.365 3 11.2503 3C9.13533 3 7.05233 3.13678 5.00963 3.40199C3.40173 3.61074 2.25 5.01598 2.25 6.63738V12.8626C2.25 14.484 3.40173 15.8893 5.00964 16.098C5.58661 16.1729 6.16679 16.2376 6.75 16.2918V21L10.9049 16.8451" />',
      'chat-bubble-left-ellipsis' => '<path stroke-linecap="round" stroke-linejoin="round" d="M8.625 9.75C8.625 9.95711 8.45711 10.125 8.25 10.125C8.04289 10.125 7.875 9.95711 7.875 9.75C7.875 9.54289 8.04289 9.375 8.25 9.375C8.45711 9.375 8.625 9.54289 8.625 9.75ZM8.625 9.75H8.25M12.375 9.75C12.375 9.95711 12.2071 10.125 12 10.125C11.7929 10.125 11.625 9.95711 11.625 9.75C11.625 9.54289 11.7929 9.375 12 9.375C12.2071 9.375 12.375 9.54289 12.375 9.75ZM12.375 9.75H12M16.125 9.75C16.125 9.95711 15.9571 10.125 15.75 10.125C15.5429 10.125 15.375 9.95711 15.375 9.75C15.375 9.54289 15.5429 9.375 15.75 9.375C15.9571 9.375 16.125 9.54289 16.125 9.75ZM16.125 9.75H15.75M2.25 12.7593C2.25 14.3604 3.37341 15.754 4.95746 15.987C6.04357 16.1467 7.14151 16.27 8.25 16.3556V21L12.4335 16.8165C12.6402 16.6098 12.9193 16.4923 13.2116 16.485C15.1872 16.4361 17.1331 16.2678 19.0425 15.9871C20.6266 15.7542 21.75 14.3606 21.75 12.7595V6.74056C21.75 5.13946 20.6266 3.74583 19.0425 3.51293C16.744 3.17501 14.3926 3 12.0003 3C9.60776 3 7.25612 3.17504 4.95747 3.51302C3.37342 3.74593 2.25 5.13956 2.25 6.74064V12.7593Z" />',
      'arrow-right' => '<path stroke-linecap="round" stroke-linejoin="round" d="M13.5 4.5L21 12M21 12L13.5 19.5M21 12H3" />',
      'arrow-left' => '<path stroke-linecap="round" stroke-linejoin="round" d="M10.5 19.5L3 12M3 12L10.5 4.5M3 12H21" />',
      'pause' => '<path stroke-linecap="round" stroke-linejoin="round" d="M15.75 5.25L15.75 18.75M8.25 5.25V18.75" />',
      'play' => '<path stroke-linecap="round" stroke-linejoin="round" d="M5.25 5.65273C5.25 4.79705 6.1674 4.25462 6.91716 4.66698L18.4577 11.0143C19.2349 11.4417 19.2349 12.5584 18.4577 12.9858L6.91716 19.3331C6.1674 19.7455 5.25 19.203 5.25 18.3474V5.65273Z" />',
      'sparkles' => '<path stroke-linecap="round" stroke-linejoin="round" d="M9.8132 15.9038L9 18.75L8.1868 15.9038C7.75968 14.4089 6.59112 13.2403 5.09619 12.8132L2.25 12L5.09619 11.1868C6.59113 10.7597 7.75968 9.59112 8.1868 8.09619L9 5.25L9.8132 8.09619C10.2403 9.59113 11.4089 10.7597 12.9038 11.1868L15.75 12L12.9038 12.8132C11.4089 13.2403 10.2403 14.4089 9.8132 15.9038Z" /><path stroke-linecap="round" stroke-linejoin="round" d="M18.2589 8.71454L18 9.75L17.7411 8.71454C17.4388 7.50533 16.4947 6.56117 15.2855 6.25887L14.25 6L15.2855 5.74113C16.4947 5.43883 17.4388 4.49467 17.7411 3.28546L18 2.25L18.2589 3.28546C18.5612 4.49467 19.5053 5.43883 20.7145 5.74113L21.75 6L20.7145 6.25887C19.5053 6.56117 18.5612 7.50533 18.2589 8.71454Z" /><path stroke-linecap="round" stroke-linejoin="round" d="M16.8942 20.5673L16.5 21.75L16.1058 20.5673C15.8818 19.8954 15.3546 19.3682 14.6827 19.1442L13.5 18.75L14.6827 18.3558C15.3546 18.1318 15.8818 17.6046 16.1058 16.9327L16.5 15.75L16.8942 16.9327C17.1182 17.6046 17.6454 18.1318 18.3173 18.3558L19.5 18.75L18.3173 19.1442C17.6454 19.3682 17.1182 19.8954 16.8942 20.5673Z" />',
      'arrow-trending-up' => '<path stroke-linecap="round" stroke-linejoin="round" d="M2.25 17.9999L9 11.2499L13.3064 15.5564C14.5101 13.188 16.5042 11.2022 19.1203 10.0375L21.8609 8.81726M21.8609 8.81726L15.9196 6.53662M21.8609 8.81726L19.5802 14.7585" />',
      'user' => '<path stroke-linecap="round" stroke-linejoin="round" d="M15.75 6C15.75 8.07107 14.071 9.75 12 9.75C9.9289 9.75 8.24996 8.07107 8.24996 6C8.24996 3.92893 9.9289 2.25 12 2.25C14.071 2.25 15.75 3.92893 15.75 6Z" /><path stroke-linecap="round" stroke-linejoin="round" d="M4.5011 20.1182C4.5714 16.0369 7.90184 12.75 12 12.75C16.0982 12.75 19.4287 16.0371 19.4988 20.1185C17.216 21.166 14.6764 21.75 12.0003 21.75C9.32396 21.75 6.78406 21.1659 4.5011 20.1182Z" />',
      'cloud' => '<path stroke-linecap="round" stroke-linejoin="round" d="M2.25 15C2.25 17.4853 4.26472 19.5 6.75 19.5H18C20.0711 19.5 21.75 17.8211 21.75 15.75C21.75 14.1479 20.7453 12.7805 19.3316 12.2433C19.4407 11.9324 19.5 11.5981 19.5 11.25C19.5 9.59315 18.1569 8.25 16.5 8.25C16.1767 8.25 15.8654 8.30113 15.5737 8.39575C14.9765 6.1526 12.9312 4.5 10.5 4.5C7.6005 4.5 5.25 6.85051 5.25 9.75C5.25 10.0832 5.28105 10.4092 5.3404 10.7252C3.54555 11.3167 2.25 13.0071 2.25 15Z" />',
      'circle' => '<path stroke-linecap="round" stroke-linejoin="round" d="M21 12C21 16.9706 16.9706 21 12 21C7.02944 21 3 16.9706 3 12C3 7.02944 7.02944 3 12 3C16.9706 3 21 7.02944 21 12Z" />',
      'document-text' => '<path stroke-linecap="round" stroke-linejoin="round" d="M19.5 14.25V11.625C19.5 9.76104 17.989 8.25 16.125 8.25H14.625C14.0037 8.25 13.5 7.74632 13.5 7.125V5.625C13.5 3.76104 11.989 2.25 10.125 2.25H8.25M8.25 15H15.75M8.25 18H12M10.5 2.25H5.625C5.00368 2.25 4.5 2.75368 4.5 3.375V20.625C4.5 21.2463 5.00368 21.75 5.625 21.75H18.375C18.9963 21.75 19.5 21.2463 19.5 20.625V11.25C19.5 6.27944 15.4706 2.25 10.5 2.25Z" />',
      'chevron-down' => '<path stroke-linecap="round" stroke-linejoin="round" d="M19.5 8.25L12 15.75L4.5 8.25" />',
      'queue-list' => '<path stroke-linecap="round" stroke-linejoin="round" d="M3.75 12H20.25M3.75 15.75H20.25M3.75 19.5H20.25M5.625 4.5H18.375C19.4105 4.5 20.25 5.33947 20.25 6.375C20.25 7.41053 19.4105 8.25 18.375 8.25H5.625C4.58947 8.25 3.75 7.41053 3.75 6.375C3.75 5.33947 4.58947 4.5 5.625 4.5Z" />',
      'inbox' => '<path stroke-linecap="round" stroke-linejoin="round" d="M2.25 13.5H6.10942C6.96166 13.5 7.74075 13.9815 8.12188 14.7438L8.37812 15.2562C8.75925 16.0185 9.53834 16.5 10.3906 16.5H13.6094C14.4617 16.5 15.2408 16.0185 15.6219 15.2562L15.8781 14.7438C16.2592 13.9815 17.0383 13.5 17.8906 13.5H21.75M2.25 13.8383V18C2.25 19.2426 3.25736 20.25 4.5 20.25H19.5C20.7426 20.25 21.75 19.2426 21.75 18V13.8383C21.75 13.614 21.7165 13.391 21.6505 13.1766L19.2387 5.33831C18.9482 4.39423 18.076 3.75 17.0882 3.75H6.91179C5.92403 3.75 5.05178 4.39423 4.76129 5.33831L2.3495 13.1766C2.28354 13.391 2.25 13.614 2.25 13.8383Z" />',
      'cpu-chip' => '<path stroke-linecap="round" stroke-linejoin="round" d="M8.25 3V4.5M4.5 8.25H3M21 8.25H19.5M4.5 12H3M21 12H19.5M4.5 15.75H3M21 15.75H19.5M8.25 19.5V21M12 3V4.5M12 19.5V21M15.75 3V4.5M15.75 19.5V21M6.75 19.5H17.25C18.4926 19.5 19.5 18.4926 19.5 17.25V6.75C19.5 5.50736 18.4926 4.5 17.25 4.5H6.75C5.50736 4.5 4.5 5.50736 4.5 6.75V17.25C4.5 18.4926 5.50736 19.5 6.75 19.5ZM7.5 7.5H16.5V16.5H7.5V7.5Z" />',
      'information-circle' => '<path stroke-linecap="round" stroke-linejoin="round" d="M11.25 11.25L11.2915 11.2293C11.8646 10.9427 12.5099 11.4603 12.3545 12.082L11.6455 14.918C11.4901 15.5397 12.1354 16.0573 12.7085 15.7707L12.75 15.75M21 12C21 16.9706 16.9706 21 12 21C7.02944 21 3 16.9706 3 12C3 7.02944 7.02944 3 12 3C16.9706 3 21 7.02944 21 12ZM12 8.25H12.0075V8.2575H12V8.25Z" />'
    }.freeze
  end
end
