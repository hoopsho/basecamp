# frozen_string_literal: true

class EmailService
  class EmailError < StandardError; end
  class ApiError < EmailError; end
  class InvalidEmailError < EmailError; end

  DEFAULT_FROM = 'noreply@eightyeightservices.com'

  def self.send(to:, subject:, body:, from: nil, html_body: nil, reply_to: nil)
    new.send_email(to, subject, body, from, html_body, reply_to)
  end

  def self.send_template(to:, template_name:, variables:, from: nil)
    new.send_template_email(to, template_name, variables, from)
  end

  def send_email(to, subject, body, from = nil, html_body = nil, reply_to = nil)
    from ||= DEFAULT_FROM

    validate_email!(to)
    validate_email!(from)

    if Rails.env.test? || Rails.env.development?
      return mock_email_response(to, subject)
    end

    # Get SES credentials
    cred = Credential.find_usable('ses', :api_key)
    unless cred
      return { success: false, error: 'No SES credentials found' }
    end

    # Build the email
    email = build_aws_email(to, from, subject, body, html_body, reply_to)

    # Send via SES
    send_via_ses(email, cred)
  rescue InvalidEmailError => e
    { success: false, error: e.message }
  rescue StandardError => e
    { success: false, error: e.message }
  end

  def send_template_email(to, template_name, variables, from = nil)
    from ||= DEFAULT_FROM

    validate_email!(to)
    validate_email!(from)

    template = load_template(template_name, variables)

    send_email(
      to: to,
      subject: template[:subject],
      body: template[:text_body],
      from: from,
      html_body: template[:html_body]
    )
  end

  def self.test_connection
    new.test_connection
  end

  def test_connection
    if Rails.env.test? || Rails.env.development?
      return { success: true, message: 'Mock connection successful' }
    end

    cred = Credential.find_usable('ses', :api_key)
    unless cred
      return { success: false, error: 'No SES credentials found' }
    end

    # Try to send a test email to ourselves
    send_email(
      to: DEFAULT_FROM,
      subject: 'SOP Engine - Email Service Test',
      body: 'This is a test email from the SOP Engine.',
      from: DEFAULT_FROM
    )
  end

  private

  def validate_email!(email)
    return if email.to_s.match?(URI::MailTo::EMAIL_REGEXP)

    raise InvalidEmailError, "Invalid email address: #{email}"
  end

  def load_template(name, variables)
    templates = {
      lead_acknowledgment: {
        subject: 'Thank you for contacting Eighty Eight Services',
        text_body: lead_acknowledgment_text(variables),
        html_body: lead_acknowledgment_html(variables)
      },
      customer_reactivation: {
        subject: "It's time for your #{variables[:season]} service!",
        text_body: reactivation_text(variables),
        html_body: reactivation_html(variables)
      },
      follow_up: {
        subject: 'Following up on your quote request',
        text_body: follow_up_text(variables),
        html_body: follow_up_html(variables)
      },
      review_request: {
        subject: 'How did we do?',
        text_body: review_request_text(variables),
        html_body: review_request_html(variables)
      },
      invoice_reminder: {
        subject: "Invoice #{variables[:invoice_number]} - Payment Reminder",
        text_body: invoice_reminder_text(variables),
        html_body: invoice_reminder_html(variables)
      }
    }

    template = templates[name.to_sym]
    raise EmailError, "Unknown template: #{name}" unless template

    template
  end

  def build_aws_email(to, from, subject, body, html_body, reply_to)
    {
      destination: {
        to_addresses: [ to ]
      },
      message: {
        subject: {
          data: subject,
          charset: 'UTF-8'
        },
        body: {}
      },
      source: from,
      reply_to_addresses: reply_to ? [ reply_to ] : nil
    }.tap do |email|
      if html_body
        email[:message][:body][:html] = {
          data: html_body,
          charset: 'UTF-8'
        }
      end

      email[:message][:body][:text] = {
        data: body,
        charset: 'UTF-8'
      }

      email.delete(:reply_to_addresses) unless reply_to
    end
  end

  def send_via_ses(email, credential)
    # In a real implementation, this would use the AWS SDK
    # For now, return a mock response

    # Mock SES response
    {
      success: true,
      message_id: "mock-#{SecureRandom.uuid}",
      to: email[:destination][:to_addresses].first,
      subject: email[:message][:subject][:data]
    }
  end

  def mock_email_response(to, subject)
    {
      success: true,
      message_id: "mock-#{SecureRandom.uuid}",
      to: to,
      subject: subject
    }
  end

  # Template content methods
  def lead_acknowledgment_text(vars)
    <<~EMAIL
      Hi #{vars[:customer_name]},

      Thank you for reaching out to Eighty Eight Services! We've received your inquiry about #{vars[:service_type]} services.

      One of our team members will review your request and get back to you within 24 hours with a personalized quote.

      In the meantime, if you have any urgent questions, please don't hesitate to call us at (651) 555-0123.

      Best regards,
      The Eighty Eight Services Team
    EMAIL
  end

  def lead_acknowledgment_html(vars)
    <<~EMAIL
      <html>
        <body>
          <p>Hi #{vars[:customer_name]},</p>
          <p>Thank you for reaching out to <strong>Eighty Eight Services</strong>! We've received your inquiry about #{vars[:service_type]} services.</p>
          <p>One of our team members will review your request and get back to you within 24 hours with a personalized quote.</p>
          <p>In the meantime, if you have any urgent questions, please don't hesitate to call us at <a href="tel:+16515550123">(651) 555-0123</a>.</p>
          <p>Best regards,<br>The Eighty Eight Services Team</p>
        </body>
      </html>
    EMAIL
  end

  def reactivation_text(vars)
    <<~EMAIL
      Hi #{vars[:customer_name]},

      We hope this email finds you well! We're reaching out because it's that time of year again - #{vars[:season]} season is here.

      Last year, we provided #{vars[:previous_service]} services for your property, and we'd love to work with you again this season.

      #{vars[:custom_note]}

      To sign up for this season, simply reply to this email or give us a call at (651) 555-0123.

      Best regards,
      Chris & Steven
      Eighty Eight Services
    EMAIL
  end

  def reactivation_html(vars)
    <<~EMAIL
      <html>
        <body>
          <p>Hi #{vars[:customer_name]},</p>
          <p>We hope this email finds you well! We're reaching out because it's that time of year again - <strong>#{vars[:season]} season</strong> is here.</p>
          <p>Last year, we provided #{vars[:previous_service]} services for your property, and we'd love to work with you again this season.</p>
          #{vars[:custom_note] ? "<p>#{vars[:custom_note]}</p>" : ''}
          <p>To sign up for this season, simply reply to this email or give us a call at <a href="tel:+16515550123">(651) 555-0123</a>.</p>
          <p>Best regards,<br>Chris & Steven<br>Eighty Eight Services</p>
        </body>
      </html>
    EMAIL
  end

  def follow_up_text(vars)
    <<~EMAIL
      Hi #{vars[:customer_name]},

      I wanted to follow up on the quote we sent you for #{vars[:service_type]} services.

      I know you're probably busy, but I didn't want you to miss out on our schedule filling up for the season.

      Do you have any questions about the quote? I'm happy to discuss any details or make adjustments.

      Just reply to this email or call us at (651) 555-0123.

      Best regards,
      Chris Bishop
      Eighty Eight Services
    EMAIL
  end

  def follow_up_html(vars)
    <<~EMAIL
      <html>
        <body>
          <p>Hi #{vars[:customer_name]},</p>
          <p>I wanted to follow up on the quote we sent you for #{vars[:service_type]} services.</p>
          <p>I know you're probably busy, but I didn't want you to miss out on our schedule filling up for the season.</p>
          <p>Do you have any questions about the quote? I'm happy to discuss any details or make adjustments.</p>
          <p>Just reply to this email or call us at <a href="tel:+16515550123">(651) 555-0123</a>.</p>
          <p>Best regards,<br>Chris Bishop<br>Eighty Eight Services</p>
        </body>
      </html>
    EMAIL
  end

  def review_request_text(vars)
    <<~EMAIL
      Hi #{vars[:customer_name]},

      Thank you for choosing Eighty Eight Services for your recent #{vars[:service_type]} service!

      We hope you were satisfied with our work. If you have a moment, we'd greatly appreciate it if you could leave us a review on Google.

      Your feedback helps us improve and helps other customers find us.

      Leave a review: https://g.page/r/YOUR_GOOGLE_BUSINESS_ID/review

      Thank you for your business!

      Best regards,
      The Eighty Eight Services Team
    EMAIL
  end

  def review_request_html(vars)
    <<~EMAIL
      <html>
        <body>
          <p>Hi #{vars[:customer_name]},</p>
          <p>Thank you for choosing <strong>Eighty Eight Services</strong> for your recent #{vars[:service_type]} service!</p>
          <p>We hope you were satisfied with our work. If you have a moment, we'd greatly appreciate it if you could leave us a review on Google.</p>
          <p>Your feedback helps us improve and helps other customers find us.</p>
          <p><a href="https://g.page/r/YOUR_GOOGLE_BUSINESS_ID/review" style="padding: 10px 20px; background: #4CAF50; color: white; text-decoration: none; border-radius: 5px;">Leave a Review</a></p>
          <p>Thank you for your business!</p>
          <p>Best regards,<br>The Eighty Eight Services Team</p>
        </body>
      </html>
    EMAIL
  end

  def invoice_reminder_text(vars)
    <<~EMAIL
      Hi #{vars[:customer_name]},

      This is a friendly reminder that invoice ##{vars[:invoice_number]} for $#{vars[:amount]} is now #{vars[:days_overdue]} days overdue.

      If you've already sent payment, please disregard this message.

      If you need to discuss payment arrangements or have any questions, please reply to this email or call us at (651) 555-0123.

      Thank you for your prompt attention to this matter.

      Best regards,
      Eighty Eight Services
      Accounts Receivable
    EMAIL
  end

  def invoice_reminder_html(vars)
    <<~EMAIL
      <html>
        <body>
          <p>Hi #{vars[:customer_name]},</p>
          <p>This is a friendly reminder that invoice <strong>##{vars[:invoice_number]}</strong> for $#{vars[:amount]} is now #{vars[:days_overdue]} days overdue.</p>
          <p>If you've already sent payment, please disregard this message.</p>
          <p>If you need to discuss payment arrangements or have any questions, please reply to this email or call us at <a href="tel:+16515550123">(651) 555-0123</a>.</p>
          <p>Thank you for your prompt attention to this matter.</p>
          <p>Best regards,<br>Eighty Eight Services<br>Accounts Receivable</p>
        </body>
      </html>
    EMAIL
  end
end
