# frozen_string_literal: true

class CrmService
  class CrmError < StandardError; end
  class RecordNotFoundError < CrmError; end
  class ApiError < CrmError; end

  # Mock customer data for development/testing
  MOCK_CUSTOMERS = [
    {
      'id' => 'mock-uuid-1',
      'name' => 'Jane Smith',
      'email' => 'jane.smith@example.com',
      'phone' => '(651) 555-0101',
      'address' => '123 Maple St, St Paul, MN 55101',
      'status' => 'past_customer',
      'services' => [ 'fertilizer', 'weed_control' ],
      'last_service_date' => '2024-09-15',
      'signed_up_for_season' => false,
      'lead_source' => 'referral',
      'notes' => 'Great customer, always pays on time'
    },
    {
      'id' => 'mock-uuid-2',
      'name' => 'Mike Johnson',
      'email' => 'mike.j@example.com',
      'phone' => '(651) 555-0102',
      'address' => '456 Oak Ave, Minneapolis, MN 55401',
      'status' => 'active_customer',
      'services' => [ 'snow_removal', 'lawn_care' ],
      'last_service_date' => '2025-01-20',
      'signed_up_for_season' => true,
      'lead_source' => 'website',
      'notes' => 'Needs spring cleanup scheduled'
    },
    {
      'id' => 'mock-uuid-3',
      'name' => 'Sarah Williams',
      'email' => 'sarah.w@example.com',
      'phone' => '(651) 555-0103',
      'address' => '789 Pine Ln, Edina, MN 55424',
      'status' => 'lead',
      'services' => [],
      'last_service_date' => nil,
      'signed_up_for_season' => false,
      'lead_source' => 'google',
      'notes' => 'Requested quote for fertilizer service'
    },
    {
      'id' => 'mock-uuid-4',
      'name' => 'David Brown',
      'email' => 'dbrown@example.com',
      'phone' => '(651) 555-0104',
      'address' => '321 Elm St, Roseville, MN 55113',
      'status' => 'past_customer',
      'services' => [ 'fertilizer', 'weed_control', 'aeration' ],
      'last_service_date' => '2024-10-30',
      'signed_up_for_season' => false,
      'lead_source' => 'referral',
      'notes' => 'May need more aggressive follow-up'
    },
    {
      'id' => 'mock-uuid-5',
      'name' => 'Lisa Davis',
      'email' => 'lisa.davis@example.com',
      'phone' => '(651) 555-0105',
      'address' => '654 Cedar Rd, Woodbury, MN 55125',
      'status' => 'active_customer',
      'services' => [ 'snow_removal' ],
      'last_service_date' => '2025-02-01',
      'signed_up_for_season' => true,
      'lead_source' => 'yard_sign',
      'notes' => 'Interested in adding lawn care services'
    }
  ].freeze

  def self.query(filters = {})
    new.query(filters)
  end

  def self.find(customer_id)
    new.find(customer_id)
  end

  def self.update(customer_id, attributes)
    new.update(customer_id, attributes)
  end

  def self.create(attributes)
    new.create(attributes)
  end

  def self.search(query)
    new.search(query)
  end

  def self.customers_for_reactivation(service_types: [ 'fertilizer', 'weed_control' ])
    new.query(
      status: 'past_customer',
      services: service_types,
      signed_up_for_season: false
    )
  end

  def self.active_leads
    new.query(status: 'lead')
  end

  def self.overdue_invoices(days_overdue: 7)
    # Mock implementation - would query CRM for overdue invoices
    []
  end

  def query(filters = {})
    if use_mock?
      mock_query(filters)
    else
      api_query(filters)
    end
  end

  def find(customer_id)
    if use_mock?
      mock_find(customer_id)
    else
      api_find(customer_id)
    end
  end

  def update(customer_id, attributes)
    if use_mock?
      mock_update(customer_id, attributes)
    else
      api_update(customer_id, attributes)
    end
  end

  def create(attributes)
    if use_mock?
      mock_create(attributes)
    else
      api_create(attributes)
    end
  end

  def search(query)
    if use_mock?
      mock_search(query)
    else
      api_search(query)
    end
  end

  def record_interaction(customer_id, interaction_type, details)
    if use_mock?
      mock_record_interaction(customer_id, interaction_type, details)
    else
      api_record_interaction(customer_id, interaction_type, details)
    end
  end

  private

  def use_mock?
    Rails.env.development? || Rails.env.test? || ENV['USE_MOCK_CRM'] == 'true'
  end

  # Mock implementations

  def mock_query(filters)
    results = MOCK_CUSTOMERS.dup

    filters.each do |key, value|
      case key
      when :status
        results.select! { |c| c['status'] == value.to_s }
      when :services
        if value.is_a?(Array)
          results.select! { |c| (c['services'] & value).any? }
        else
          results.select! { |c| c['services'].include?(value.to_s) }
        end
      when :signed_up_for_season
        results.select! { |c| c['signed_up_for_season'] == value }
      when :lead_source
        results.select! { |c| c['lead_source'] == value.to_s }
      end
    end

    {
      success: true,
      customers: results,
      count: results.size
    }
  end

  def mock_find(customer_id)
    customer = MOCK_CUSTOMERS.find { |c| c['id'] == customer_id }

    unless customer
      raise RecordNotFoundError, "Customer not found: #{customer_id}"
    end

    {
      success: true,
      customer: customer
    }
  end

  def mock_update(customer_id, attributes)
    customer = MOCK_CUSTOMERS.find { |c| c['id'] == customer_id }

    unless customer
      raise RecordNotFoundError, "Customer not found: #{customer_id}"
    end

    customer.merge!(attributes.stringify_keys)

    {
      success: true,
      customer: customer
    }
  end

  def mock_create(attributes)
    new_customer = attributes.stringify_keys.merge(
      'id' => "mock-uuid-#{SecureRandom.hex(8)}"
    )

    {
      success: true,
      customer: new_customer
    }
  end

  def mock_search(query)
    term = query.to_s.downcase

    results = MOCK_CUSTOMERS.select do |c|
      c['name'].downcase.include?(term) ||
      c['email'].downcase.include?(term) ||
      c['address'].downcase.include?(term)
    end

    {
      success: true,
      customers: results,
      count: results.size,
      query: query
    }
  end

  def mock_record_interaction(customer_id, interaction_type, details)
    {
      success: true,
      interaction_id: "interaction-#{SecureRandom.hex(8)}",
      customer_id: customer_id,
      type: interaction_type,
      timestamp: Time.current.iso8601
    }
  end

  # Real API implementations (placeholders for future CRM integration)

  def api_query(filters)
    raise NotImplementedError, 'CRM API integration not yet implemented'
  end

  def api_find(customer_id)
    raise NotImplementedError, 'CRM API integration not yet implemented'
  end

  def api_update(customer_id, attributes)
    raise NotImplementedError, 'CRM API integration not yet implemented'
  end

  def api_create(attributes)
    raise NotImplementedError, 'CRM API integration not yet implemented'
  end

  def api_search(query)
    raise NotImplementedError, 'CRM API integration not yet implemented'
  end

  def api_record_interaction(customer_id, interaction_type, details)
    raise NotImplementedError, 'CRM API integration not yet implemented'
  end
end
