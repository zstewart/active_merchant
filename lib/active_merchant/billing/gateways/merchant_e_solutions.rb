module ActiveMerchant # :nodoc:
  module Billing # :nodoc:
    class MerchantESolutionsGateway < Gateway
      include Empty

      self.test_url = 'https://cert.merchante-solutions.com/mes-api/tridentApi'
      self.live_url = 'https://api.merchante-solutions.com/mes-api/tridentApi'

      # The countries the gateway supports merchants from as 2 digit ISO country codes
      self.supported_countries = ['US']

      # The card types supported by the payment gateway
      self.supported_cardtypes = %i[visa master american_express discover jcb]

      # The homepage URL of the gateway
      self.homepage_url = 'http://www.merchante-solutions.com/'

      # The name of the gateway
      self.display_name = 'Merchant e-Solutions'

      SUCCESS_RESPONSE_CODES = %w(000 085)

      def initialize(options = {})
        requires!(options, :login, :password)
        super
      end

      def authorize(money, creditcard_or_card_id, options = {})
        post = {}
        add_invoice(post, options)
        add_payment_source(post, creditcard_or_card_id, options)
        add_address(post, options)
        add_3dsecure_params(post, options)
        add_stored_credentials(post, options)
        commit('P', money, post)
      end

      def purchase(money, creditcard_or_card_id, options = {})
        post = {}
        add_invoice(post, options)
        add_payment_source(post, creditcard_or_card_id, options)
        add_address(post, options)
        add_3dsecure_params(post, options)
        add_stored_credentials(post, options)
        commit('D', money, post)
      end

      def capture(money, transaction_id, options = {})
        post = {}
        post[:transaction_id] = transaction_id
        post[:client_reference_number] = options[:customer] if options.has_key?(:customer)
        add_invoice(post, options)
        add_3dsecure_params(post, options)
        commit('S', money, post)
      end

      def store(creditcard, options = {})
        MultiResponse.run do |r|
          r.process { temporary_store(creditcard, options) }
          r.process { verify(r.authorization, { store_card: 'y' }) }
        end
      end

      def unstore(card_id, options = {})
        post = {}
        post[:client_reference_number] = options[:customer] if options.has_key?(:customer)
        post[:card_id] = card_id
        commit('X', nil, post)
      end

      def refund(money, identification, options = {})
        post = {}
        post[:transaction_id] = identification
        post[:client_reference_number] = options[:customer] if options.has_key?(:customer)
        options.delete(:customer)
        options.delete(:billing_address)
        commit('U', money, options.merge(post))
      end

      def credit(money, creditcard_or_card_id, options = {})
        post = {}
        post[:client_reference_number] = options[:customer] if options.has_key?(:customer)
        add_invoice(post, options)
        add_payment_source(post, creditcard_or_card_id, options)
        commit('C', money, post)
      end

      def void(transaction_id, options = {})
        post = {}
        post[:transaction_id] = transaction_id
        post[:client_reference_number] = options[:customer] if options.has_key?(:customer)
        options.delete(:customer)
        options.delete(:billing_address)
        commit('V', nil, options.merge(post))
      end

      def verify(credit_card, options = {})
        post = {}
        post[:store_card] = options[:store_card] if options[:store_card]
        add_payment_source(post, credit_card, options)
        commit('A', 0, post)
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript.
          gsub(%r((&?profile_key=)\w*(&?)), '\1[FILTERED]\2').
          gsub(%r((&?card_number=)\d*(&?)), '\1[FILTERED]\2').
          gsub(%r((&?cvv2=)\d*(&?)), '\1[FILTERED]\2')
      end

      private

      def temporary_store(creditcard, options = {})
        post = {}
        post[:client_reference_number] = options[:customer] if options.has_key?(:customer)
        add_creditcard(post, creditcard, options)
        commit('T', nil, post)
      end

      def add_address(post, options)
        if address = options[:billing_address] || options[:address]
          post[:cardholder_street_address] = address[:address1].to_s.gsub(/[^\w.]/, '+')
          post[:cardholder_zip] = address[:zip].to_s
        end
      end

      def add_invoice(post, options)
        if options.has_key? :order_id
          order_id = options[:order_id].to_s.gsub(/[^\w.]/, '')
          post[:invoice_number] = truncate(order_id, 17)
        end
      end

      def add_payment_source(post, creditcard_or_card_id, options)
        if creditcard_or_card_id.is_a?(String)
          # using stored card
          post[:card_id] = creditcard_or_card_id
          post[:card_exp_date] = options[:expiration_date] if options[:expiration_date]
        else
          # card info is provided
          add_creditcard(post, creditcard_or_card_id, options)
        end
      end

      def add_creditcard(post, creditcard, options)
        post[:card_number] = creditcard.number
        post[:cvv2] = creditcard.verification_value if creditcard.verification_value?
        post[:card_exp_date] = expdate(creditcard)
      end

      def add_3dsecure_params(post, options)
        post[:xid] = options[:xid] unless empty?(options[:xid])
        post[:cavv] = options[:cavv] unless empty?(options[:cavv])
        post[:ucaf_collection_ind] = options[:ucaf_collection_ind] unless empty?(options[:ucaf_collection_ind])
        post[:ucaf_auth_data] = options[:ucaf_auth_data] unless empty?(options[:ucaf_auth_data])
      end

      def add_stored_credentials(post, options)
        post[:client_reference_number] = options[:client_reference_number] if options[:client_reference_number]
        post[:moto_ecommerce_ind] = options[:moto_ecommerce_ind] if options[:moto_ecommerce_ind]
        post[:recurring_pmt_num] = options[:recurring_pmt_num] if options[:recurring_pmt_num]
        post[:recurring_pmt_count] = options[:recurring_pmt_count] if options[:recurring_pmt_count]
        post[:card_on_file] = options[:card_on_file] if options[:card_on_file]
        post[:cit_mit_indicator] = options[:cit_mit_indicator] if options[:cit_mit_indicator]
        post[:account_data_source] = options[:account_data_source] if options[:account_data_source]
      end

      def parse(body)
        results = {}
        body.split(/&/).each do |pair|
          key, val = pair.split(/=/)
          results[key] = val
        end
        results
      end

      def commit(action, money, parameters)
        url = test? ? self.test_url : self.live_url
        parameters[:transaction_amount] = amount(money) if !(action == 'V') && money

        response =
          begin
            parse(ssl_post(url, post_data(action, parameters)))
          rescue ActiveMerchant::ResponseError => e
            { 'error_code' => '404', 'auth_response_text' => e.to_s }
          end

        Response.new(
          success_from(response),
          message_from(response),
          response,
          authorization: authorization_from(response),
          test: test?,
          cvv_result: response['cvv2_result'],
          avs_result: { code: response['avs_result'] }
        )
      end

      def authorization_from(response)
        return response['card_id'] if response['card_id']

        response['transaction_id']
      end

      def success_from(response)
        SUCCESS_RESPONSE_CODES.include?(response['error_code'])
      end

      def message_from(response)
        if response['error_code'] == '000'
          'This transaction has been approved'
        else
          response['auth_response_text']
        end
      end

      def post_data(action, parameters = {})
        post = {}
        post[:profile_id] = @options[:login]
        post[:profile_key] = @options[:password]
        post[:transaction_type] = action if action

        post.merge(parameters).map { |key, value| "#{key}=#{CGI.escape(value.to_s)}" }.join('&')
      end
    end
  end
end
