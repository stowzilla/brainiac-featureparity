# frozen_string_literal: true

require "openssl"
require "base64"

module Brainiac
  module Plugins
    module Featureparity
      # Verifies a FeatureParity delivery (Standard Webhooks, standardwebhooks.com).
      #
      # FeatureParity signs every delivery with the secret of whatever it was sent to: a
      # project webhook, or an agent key's wake-up address. Each is a "whsec_<base64>"
      # string shown once in FeatureParity. The signature is
      # base64(HMAC-SHA256(key, "<webhook-id>.<webhook-timestamp>.<raw body>")) where the
      # key is the base64-decoded part after "whsec_", sent as "v1,<signature>".
      module Signature
        # Reject deliveries stamped more than this far from now, so a captured request
        # can't be replayed later.
        TOLERANCE = 300

        module_function

        # True when `signature` (the webhook-signature header, which may hold several
        # space-separated "v1,..." values) matches the body under any of `secrets`.
        def valid?(secrets:, id:, timestamp:, signature:, body:, now: Time.now.to_i)
          return false if id.to_s.empty? || !fresh?(timestamp, now)

          offered = offered_signatures(signature)
          Array(secrets).any? do |secret|
            expected = sign(secret, id, timestamp, body)
            offered.any? { |sig| secure_compare(sig, expected) }
          end
        end

        def fresh?(timestamp, now)
          timestamp.to_s.match?(/\A\d+\z/) && (now - timestamp.to_i).abs <= TOLERANCE
        end

        # The v1 signatures in a webhook-signature header ("v1,<sig> v1,<sig>").
        def offered_signatures(header)
          header.to_s.split.filter_map { |part| part.split(",", 2).last if part.start_with?("v1,") }
        end

        def sign(secret, id, timestamp, body)
          key = Base64.decode64(secret.to_s.delete_prefix("whsec_"))
          Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", key, "#{id}.#{timestamp}.#{body}"))
        end

        def secure_compare(given, expected)
          return false unless given.bytesize == expected.bytesize

          OpenSSL.fixed_length_secure_compare(given, expected)
        end
      end

      # Remembers what was just handled, so a retried delivery (same webhook-id) or the same
      # event arriving twice (a project webhook and an agent's wake-up address both
      # subscribed) dispatches one agent, not two. In memory: a restart forgets, which at
      # worst means one repeat.
      module Dedupe
        TTL = 3600
        MAX = 2000
        @seen = {}
        @lock = Mutex.new

        module_function

        # Records `key` and returns true if it was already seen within TTL.
        def seen?(key, now: Time.now.to_f)
          return false if key.to_s.empty?

          @lock.synchronize do
            @seen.delete_if { |_, at| now - at > TTL } if @seen.size >= MAX
            if (at = @seen[key]) && now - at <= TTL
              true
            else
              @seen[key] = now
              false
            end
          end
        end

        def reset!
          @lock.synchronize { @seen.clear }
        end
      end
    end
  end
end
