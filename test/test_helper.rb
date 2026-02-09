ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
require 'rails/test_help'

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

# Helper for Slack webhook tests.
# In test env with the slack_webhook_secret credential revoked (status: 2),
# the controller skips HMAC verification and only checks header presence
# and timestamp freshness. These helpers provide valid timestamp headers.
module SlackSignatureHelper
  def slack_test_headers(timestamp: Time.now.to_i.to_s)
    {
      'X-Slack-Request-Timestamp' => timestamp,
      'X-Slack-Signature' => 'v0=test-placeholder'
    }
  end
end
