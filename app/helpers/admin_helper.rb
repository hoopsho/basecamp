# frozen_string_literal: true

module AdminHelper
  # Returns the appropriate CSS class for a sidebar nav item based on current controller
  def sidebar_link_classes(controller_name, additional_classes = '')
    base_classes = 'group flex items-center px-3 py-2 text-sm font-medium rounded-lg transition-colors duration-150'

    if current_controller?(controller_name)
      active_classes = 'bg-primary-100 dark:bg-primary-900/30 text-primary-700 dark:text-primary-300'
    else
      active_classes = 'text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-700 hover:text-gray-900 dark:hover:text-gray-100'
    end

    "#{base_classes} #{active_classes} #{additional_classes}".strip
  end

  # Returns the icon color class for a sidebar nav item
  def sidebar_icon_classes(controller_name)
    if current_controller?(controller_name)
      'text-primary-600 dark:text-primary-400'
    else
      'text-gray-400 dark:text-gray-500 group-hover:text-gray-500 dark:group-hover:text-gray-400'
    end
  end

  # Check if the given controller is the current controller
  def current_controller?(name)
    controller.controller_name == name.to_s
  end

  # Returns a status badge for an agent status
  def agent_status_badge(status)
    base_classes = 'inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium'

    status_classes = case status.to_s
    when 'active'
                       'bg-green-100 dark:bg-green-900/30 text-green-800 dark:text-green-200'
    when 'paused'
                       'bg-yellow-100 dark:bg-yellow-900/30 text-yellow-800 dark:text-yellow-200'
    when 'disabled'
                       'bg-gray-100 dark:bg-gray-700 text-gray-800 dark:text-gray-200'
    else
                       'bg-gray-100 dark:bg-gray-700 text-gray-800 dark:text-gray-200'
    end

    content_tag(:span, class: "#{base_classes} #{status_classes}") do
      status.to_s.humanize
    end
  end

  # Returns a status badge for credential status
  def credential_status_badge(status)
    base_classes = 'inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium'

    status_classes = case status.to_s
    when 'active'
                       'bg-green-100 dark:bg-green-900/30 text-green-800 dark:text-green-200'
    when 'expired'
                       'bg-red-100 dark:bg-red-900/30 text-red-800 dark:text-red-200'
    when 'revoked'
                       'bg-gray-100 dark:bg-gray-700 text-gray-800 dark:text-gray-200'
    else
                       'bg-gray-100 dark:bg-gray-700 text-gray-800 dark:text-gray-200'
    end

    content_tag(:span, class: "#{base_classes} #{status_classes}") do
      status.to_s.humanize
    end
  end

  # Returns a tier badge for LLM tier display
  def tier_badge(tier)
    return content_tag(:span, 'N/A', class: 'text-gray-400 dark:text-gray-500 text-sm') if tier.nil?

    base_classes = 'inline-flex items-center px-2 py-0.5 rounded text-xs font-medium'

    tier_classes = case tier.to_i
    when 0
                     'bg-gray-100 dark:bg-gray-700 text-gray-800 dark:text-gray-200'
    when 1
                     'bg-blue-100 dark:bg-blue-900/30 text-blue-800 dark:text-blue-200'
    when 2
                     'bg-purple-100 dark:bg-purple-900/30 text-purple-800 dark:text-purple-200'
    when 3
                     'bg-amber-100 dark:bg-amber-900/30 text-amber-800 dark:text-amber-200'
    else
                     'bg-gray-100 dark:bg-gray-700 text-gray-800 dark:text-gray-200'
    end

    tier_label = case tier.to_i
    when 0 then 'Tier 0 (Ruby)'
    when 1 then 'Tier 1 (Haiku)'
    when 2 then 'Tier 2 (Sonnet)'
    when 3 then 'Tier 3 (Opus)'
    else "Tier #{tier}"
    end

    content_tag(:span, class: "#{base_classes} #{tier_classes}") do
      tier_label
    end
  end

  # Returns formatted currency amount
  def format_cost(amount)
    number_to_currency(amount, precision: 4)
  end

  # Returns relative time with a tooltip for exact time
  def time_with_tooltip(time)
    return '-' if time.nil?

    content_tag(:span, title: time.strftime('%Y-%m-%d %H:%M:%S %Z')) do
      time_ago_in_words(time) + ' ago'
    end
  end

  # Returns a boolean checkmark or X
  def boolean_icon(value)
    if value
      content_tag(:span, class: 'text-green-600 dark:text-green-400') do
        svg_icon('check-circle', class: 'w-5 h-5')
      end
    else
      content_tag(:span, class: 'text-red-600 dark:text-red-400') do
        svg_icon('x-circle', class: 'w-5 h-5')
      end
    end
  end

  # Helper to render inline SVG icons (fallback for when heroicon gem is not available)
  def svg_icon(name, options = {})
    icons = {
      'check-circle' => '<svg class="%{class}" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/></svg>',
      'x-circle' => '<svg class="%{class}" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z"/></svg>',
      'exclamation-triangle' => '<svg class="%{class}" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/></svg>',
      'information-circle' => '<svg class="%{class}" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/></svg>'
    }

    svg = icons[name] || icons['information-circle']
    class_name = options[:class] || 'w-5 h-5'

    raw(svg % { class: class_name })
  end

  # --- Credential index helpers ---

  # Returns CSS classes for credential service color badge background
  def service_color_class(service_name)
    case service_name.to_s.downcase
    when 'slack'
      'bg-purple-100 dark:bg-purple-900/30'
    when 'anthropic', 'claude'
      'bg-orange-100 dark:bg-orange-900/30'
    when 'ses', 'email'
      'bg-yellow-100 dark:bg-yellow-900/30'
    when 'crm'
      'bg-blue-100 dark:bg-blue-900/30'
    else
      'bg-gray-100 dark:bg-gray-700'
    end
  end

  # Returns SVG icon for a credential service
  def service_icon(service_name)
    icon_class = case service_name.to_s.downcase
    when 'slack'
      'text-purple-600 dark:text-purple-400'
    when 'anthropic', 'claude'
      'text-orange-600 dark:text-orange-400'
    when 'ses', 'email'
      'text-yellow-600 dark:text-yellow-400'
    when 'crm'
      'text-blue-600 dark:text-blue-400'
    else
      'text-gray-600 dark:text-gray-400'
    end

    content_tag(:svg, class: "w-5 h-5 #{icon_class}", fill: 'none', stroke: 'currentColor', viewBox: '0 0 24 24') do
      case service_name.to_s.downcase
      when 'slack'
        content_tag(:path, nil, d: 'M5.042 15.165a2.528 2.528 0 0 1-2.52 2.523A2.528 2.528 0 0 1 0 15.165a2.527 2.527 0 0 1 2.522-2.52h2.52v2.52zM6.313 15.165a2.527 2.527 0 0 1 2.521-2.52 2.527 2.527 0 0 1 2.521 2.52v6.313A2.528 2.528 0 0 1 8.834 24a2.528 2.528 0 0 1-2.521-2.522v-6.313zM8.834 5.042a2.528 2.528 0 0 1-2.521-2.52A2.528 2.528 0 0 1 8.834 0a2.528 2.528 0 0 1 2.521 2.522v2.52H8.834zM8.834 6.313a2.528 2.528 0 0 1 2.521 2.521 2.528 2.528 0 0 1-2.521 2.521H2.522A2.528 2.528 0 0 1 0 8.834a2.528 2.528 0 0 1 2.522-2.521h6.312zM18.956 8.834a2.528 2.528 0 0 1 2.522-2.521A2.528 2.528 0 0 1 24 8.834a2.528 2.528 0 0 1-2.522 2.521h-2.522V8.834zM17.688 8.834a2.528 2.528 0 0 1-2.523 2.521 2.527 2.527 0 0 1-2.52-2.521V2.522A2.527 2.527 0 0 1 15.165 0a2.528 2.528 0 0 1 2.523 2.522v6.312zM15.165 18.956a2.528 2.528 0 0 1 2.523 2.522A2.528 2.528 0 0 1 15.165 24a2.527 2.527 0 0 1-2.52-2.522v-2.522h2.52zM15.165 17.688a2.527 2.527 0 0 1-2.52-2.523 2.526 2.526 0 0 1 2.52-2.52h6.313A2.527 2.527 0 0 1 24 15.165a2.528 2.528 0 0 1-2.522 2.523h-6.313z', fill: 'currentColor')
      when 'ses', 'email'
        content_tag(:path, nil, 'stroke-linecap': 'round', 'stroke-linejoin': 'round', 'stroke-width': '1.5', d: 'M21.75 6.75v10.5a2.25 2.25 0 01-2.25 2.25h-15a2.25 2.25 0 01-2.25-2.25V6.75m19.5 0A2.25 2.25 0 0019.5 4.5h-15a2.25 2.25 0 00-2.25 2.25m19.5 0v.243a2.25 2.25 0 01-1.07 1.916l-7.5 4.615a2.25 2.25 0 01-2.36 0L3.32 8.91a2.25 2.25 0 01-1.07-1.916V6.75')
      when 'crm'
        content_tag(:path, nil, 'stroke-linecap': 'round', 'stroke-linejoin': 'round', 'stroke-width': '1.5', d: 'M15 19.128a9.38 9.38 0 002.625.372 9.337 9.337 0 004.121-.952 4.125 4.125 0 00-7.533-2.493M15 19.128v-.003c0-1.113-.285-2.16-.786-3.07M15 19.128v.106A12.318 12.318 0 018.624 21c-2.331 0-4.512-.645-6.374-1.766l-.001-.109a6.375 6.375 0 0111.964-3.07M12 6.375a3.375 3.375 0 11-6.75 0 3.375 3.375 0 016.75 0zm8.25 2.25a2.625 2.625 0 11-5.25 0 2.625 2.625 0 015.25 0z')
      else
        content_tag(:path, nil, 'stroke-linecap': 'round', 'stroke-linejoin': 'round', 'stroke-width': '1.5', d: 'M15.75 5.25a3 3 0 013 3m3 0a6 6 0 01-7.029 5.912c-.563-.097-1.159.026-1.563.43L10.5 17.25H8.25v2.25H6v2.25H2.25v-2.818c0-.597.237-1.17.659-1.591l6.499-6.499c.404-.404.527-1 .43-1.563A6 6 0 1121.75 8.25z')
      end
    end
  end

  # Returns SVG icon for a credential type
  def credential_type_icon(type)
    case type
    when 'api_key'
      content_tag(:svg, class: 'w-4 h-4', fill: 'none', stroke: 'currentColor', viewBox: '0 0 24 24') do
        content_tag(:path, nil, 'stroke-linecap': 'round', 'stroke-linejoin': 'round', 'stroke-width': '1.5', d: 'M15.75 5.25a3 3 0 013 3m3 0a6 6 0 01-7.029 5.912c-.563-.097-1.159.026-1.563.43L10.5 17.25H8.25v2.25H6v2.25H2.25v-2.818c0-.597.237-1.17.659-1.591l6.499-6.499c.404-.404.527-1 .43-1.563A6 6 0 1121.75 8.25z')
      end
    when 'oauth_token'
      content_tag(:svg, class: 'w-4 h-4', fill: 'none', stroke: 'currentColor', viewBox: '0 0 24 24') do
        content_tag(:path, nil, 'stroke-linecap': 'round', 'stroke-linejoin': 'round', 'stroke-width': '1.5', d: 'M15.75 6a3.75 3.75 0 11-7.5 0 3.75 3.75 0 017.5 0zM4.501 20.118a7.5 7.5 0 0114.998 0A17.933 17.933 0 0112 21.75c-2.676 0-5.216-.584-7.499-1.632z')
      end
    when 'webhook_secret'
      content_tag(:svg, class: 'w-4 h-4', fill: 'none', stroke: 'currentColor', viewBox: '0 0 24 24') do
        content_tag(:path, nil, 'stroke-linecap': 'round', 'stroke-linejoin': 'round', 'stroke-width': '1.5', d: 'M2.036 12.322a1.012 1.012 0 010-.639C3.423 7.51 7.36 4.5 12 4.5c4.638 0 8.573 3.007 9.963 7.178.07.207.07.431 0 .639C20.577 16.49 16.64 19.5 12 19.5c-4.638 0-8.573-3.007-9.963-7.178z')
        content_tag(:path, nil, 'stroke-linecap': 'round', 'stroke-linejoin': 'round', 'stroke-width': '1.5', d: 'M15 12a3 3 0 11-6 0 3 3 0 016 0z')
      end
    end
  end

  # Returns CSS classes for credential status dot color
  def status_dot_color(credential)
    case credential.status
    when 'active'
      credential.expires_soon? ? 'bg-yellow-500' : 'bg-green-500'
    when 'expired'
      'bg-red-500'
    when 'revoked'
      'bg-gray-500'
    end
  end

  # --- Credential show helpers ---

  # Returns CSS classes for the status banner background and border
  def status_banner_classes(credential)
    case credential.status
    when 'active'
      if credential.expires_soon?
        'bg-yellow-50 dark:bg-yellow-900/20 border border-yellow-200 dark:border-yellow-800'
      else
        'bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800'
      end
    when 'expired'
      'bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800'
    when 'revoked'
      'bg-gray-50 dark:bg-gray-800 border border-gray-200 dark:border-gray-700'
    end
  end

  # Returns CSS classes for the status icon background circle
  def status_icon_background(credential)
    case credential.status
    when 'active'
      if credential.expires_soon?
        'bg-yellow-100 dark:bg-yellow-900/40'
      else
        'bg-green-100 dark:bg-green-900/40'
      end
    when 'expired'
      'bg-red-100 dark:bg-red-900/40'
    when 'revoked'
      'bg-gray-200 dark:bg-gray-700'
    end
  end

  # Returns CSS classes for the status icon stroke color
  def status_icon_color(credential)
    case credential.status
    when 'active'
      if credential.expires_soon?
        'text-yellow-600 dark:text-yellow-400'
      else
        'text-green-600 dark:text-green-400'
      end
    when 'expired'
      'text-red-600 dark:text-red-400'
    when 'revoked'
      'text-gray-500 dark:text-gray-400'
    end
  end

  # Returns CSS classes for the status heading text color
  def status_text_color(credential)
    case credential.status
    when 'active'
      if credential.expires_soon?
        'text-yellow-800 dark:text-yellow-200'
      else
        'text-green-800 dark:text-green-200'
      end
    when 'expired'
      'text-red-800 dark:text-red-200'
    when 'revoked'
      'text-gray-700 dark:text-gray-300'
    end
  end

  # Returns CSS classes for the status subtitle text color
  def status_subtext_color(credential)
    case credential.status
    when 'active'
      if credential.expires_soon?
        'text-yellow-600 dark:text-yellow-400'
      else
        'text-green-600 dark:text-green-400'
      end
    when 'expired'
      'text-red-600 dark:text-red-400'
    when 'revoked'
      'text-gray-500 dark:text-gray-400'
    end
  end

  # Returns a human-readable status message for a credential
  def status_message(credential)
    case credential.status
    when 'active'
      if credential.expires_soon?
        "This credential will expire in #{credential.days_until_expiration} days"
      else
        'This credential is active and working normally'
      end
    when 'expired'
      'This credential has expired and cannot be used'
    when 'revoked'
      'This credential has been revoked'
    end
  end

  # Returns CSS classes for the expiration info box background
  def expiration_box_class(credential)
    if credential.expired?
      'bg-red-50 dark:bg-red-900/20'
    elsif credential.expires_soon?
      'bg-yellow-50 dark:bg-yellow-900/20'
    else
      'bg-green-50 dark:bg-green-900/20'
    end
  end

  # Returns CSS classes for the expiration icon color
  def expiration_icon_color(credential)
    if credential.expired?
      'text-red-500'
    elsif credential.expires_soon?
      'text-yellow-500'
    else
      'text-green-500'
    end
  end

  # Returns CSS classes for the expiration text color
  def expiration_text_color(credential)
    if credential.expired?
      'text-red-700 dark:text-red-300'
    elsif credential.expires_soon?
      'text-yellow-700 dark:text-yellow-300'
    else
      'text-green-700 dark:text-green-300'
    end
  end

  # Returns CSS classes for the expiration subtext color
  def expiration_subtext_color(credential)
    if credential.expired?
      'text-red-600 dark:text-red-400'
    elsif credential.expires_soon?
      'text-yellow-600 dark:text-yellow-400'
    else
      'text-green-600 dark:text-green-400'
    end
  end
end
