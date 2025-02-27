require 'test_helper'

class GlobalCollectTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = GlobalCollectGateway.new(merchant_id: '1234',
                                        api_key_id: '39u4193urng12',
                                        secret_api_key: '109H/288H*50Y18W4/0G8571F245KA=')
    @gateway_direct = GlobalCollectGateway.new(fixtures(:global_collect_direct))
    @gateway_direct.options[:url_override] = 'ogone_direct'

    @credit_card = credit_card('4567350000427977')
    @apple_pay_network_token = network_tokenization_credit_card(
      '4444333322221111',
      month: 10,
      year: 24,
      first_name: 'John',
      last_name: 'Smith',
      eci: '05',
      payment_cryptogram: 'EHuWW9PiBkWvqE5juRwDzAUFBAk=',
      source: :apple_pay
    )

    @google_pay_network_token = ActiveMerchant::Billing::NetworkTokenizationCreditCard.new({
      source: :google_pay,
      payment_data: { 'version' => 'EC_v1', 'data' => 'QlzLxRFnNP9/GTaMhBwgmZ2ywntbr9' }
    })

    @declined_card = credit_card('5424180279791732')
    @accepted_amount = 4005
    @rejected_amount = 2997
    @options = {
      billing_address: address,
      description: 'Store Purchase'
    }
    @options_3ds2 = @options.merge(
      three_d_secure: {
        version: '2.1.0',
        eci: '05',
        cavv: 'jJ81HADVRtXfCBATEp01CJUAAAA=',
        xid: 'BwABBJQ1AgAAAAAgJDUCAAAAAAA=',
        ds_transaction_id: '97267598-FAE6-48F2-8083-C23433990FBC',
        acs_transaction_id: '13c701a3-5a88-4c45-89e9-ef65e50a8bf9',
        cavv_algorithm: 1,
        authentication_response_status: 'Y',
        flow: 'frictionless'
      }
    )
  end

  def test_url
    url = @gateway.test? ? @gateway.test_url : @gateway.live_url
    merchant_id = @gateway.options[:merchant_id]
    assert_equal "#{url}/v1/#{merchant_id}/payments", @gateway.send(:url, :authorize, nil)
    assert_equal "#{url}/v1/#{merchant_id}/payments", @gateway.send(:url, :verify, nil)
    assert_equal "#{url}/v1/#{merchant_id}/payments/0000/approve", @gateway.send(:url, :capture, '0000')
    assert_equal "#{url}/v1/#{merchant_id}/payments/0000/refund", @gateway.send(:url, :refund, '0000')
    assert_equal "#{url}/v1/#{merchant_id}/payments/0000/cancel", @gateway.send(:url, :void, '0000')
    assert_equal "#{url}/v1/#{merchant_id}/payments/0000", @gateway.send(:url, :inquire, '0000')
  end

  def test_ogone_url
    url = @gateway_direct.test? ? @gateway_direct.ogone_direct_test : @gateway_direct.ogone_direct_live
    merchant_id = @gateway_direct.options[:merchant_id]
    assert_equal "#{url}/v2/#{merchant_id}/payments", @gateway_direct.send(:url, :authorize, nil)
    assert_equal "#{url}/v2/#{merchant_id}/payments", @gateway_direct.send(:url, :verify, nil)
    assert_equal "#{url}/v2/#{merchant_id}/payments/0000/capture", @gateway_direct.send(:url, :capture, '0000')
    assert_equal "#{url}/v2/#{merchant_id}/payments/0000/refund", @gateway_direct.send(:url, :refund, '0000')
    assert_equal "#{url}/v2/#{merchant_id}/payments/0000/cancel", @gateway_direct.send(:url, :void, '0000')
    assert_equal "#{url}/v2/#{merchant_id}/payments/0000", @gateway_direct.send(:url, :inquire, '0000')
  end

  def test_supported_card_types
    assert_equal GlobalCollectGateway.supported_cardtypes, %i[visa master american_express discover naranja cabal tuya patagonia_365 tarjeta_sol]
  end

  def test_successful_authorize_and_capture
    response = stub_comms(@gateway, :ssl_request) do
      @gateway.authorize(@accepted_amount, @credit_card, @options)
    end.respond_with(successful_authorize_response)

    assert_success response
    assert_equal '000000142800000000920000100001', response.authorization

    capture = stub_comms(@gateway, :ssl_request) do
      @gateway.capture(@accepted_amount, response.authorization)
    end.check_request do |_method, endpoint, _data, _headers|
      assert_match(/000000142800000000920000100001/, endpoint)
    end.respond_with(successful_capture_response)

    assert_success capture
  end

  def test_successful_preproduction_url
    @gateway = GlobalCollectGateway.new(
      merchant_id: '1234',
      api_key_id: '39u4193urng12',
      secret_api_key: '109H/288H*50Y18W4/0G8571F245KA=',
      url_override: 'preproduction'
    )

    stub_comms(@gateway, :ssl_request) do
      @gateway.authorize(@accepted_amount, @credit_card)
    end.check_request do |_method, endpoint, _data, _headers|
      assert_match(/api\.preprod\.connect\.worldline-solutions\.com\/v1\/#{@gateway.options[:merchant_id]}/, endpoint)
    end.respond_with(successful_authorize_response)
  end

  # When requires_approval is true (or not present),
  # a `purchase` makes two calls (`auth` and `capture`).
  def test_successful_purchase_with_requires_approval_true
    stub_comms(@gateway, :ssl_request) do
      @gateway.purchase(@accepted_amount, @credit_card, @options.merge(requires_approval: true))
    end.check_request do |_method, _endpoint, _data, _headers|
    end.respond_with(successful_authorize_response, successful_capture_response)
  end

  def test_purchase_request_with_encrypted_google_pay
    google_pay = ActiveMerchant::Billing::NetworkTokenizationCreditCard.new({
      source: :google_pay,
      payment_data: { 'version' => 'EC_v1', 'data' => 'QlzLxRFnNP9/GTaMhBwgmZ2ywntbr9' }
    })

    stub_comms(@gateway, :ssl_request) do
      @gateway.purchase(@accepted_amount, google_pay, { use_encrypted_payment_data: true })
    end.check_request(skip_response: true) do |_method, _endpoint, data, _headers|
      assert_equal '320', JSON.parse(data)['mobilePaymentMethodSpecificInput']['paymentProductId']
      assert_equal google_pay.payment_data.to_s&.gsub('=>', ':'), JSON.parse(data)['mobilePaymentMethodSpecificInput']['encryptedPaymentData']
    end
  end

  def test_purchase_request_with_google_pay
    stub_comms(@gateway, :ssl_request) do
      @gateway.purchase(@accepted_amount, @google_pay_network_token)
    end.check_request(skip_response: true) do |_method, _endpoint, data, _headers|
      assert_equal '320', JSON.parse(data)['mobilePaymentMethodSpecificInput']['paymentProductId']
    end
  end

  def test_add_payment_for_credit_card
    post = {}
    options = {}
    payment = @credit_card
    @gateway.send('add_payment', post, payment, options)
    assert_includes post.keys, 'cardPaymentMethodSpecificInput'
    assert_equal post['cardPaymentMethodSpecificInput']['paymentProductId'], '1'
    assert_equal post['cardPaymentMethodSpecificInput']['authorizationMode'], 'FINAL_AUTHORIZATION'
    assert_includes post['cardPaymentMethodSpecificInput'].keys, 'card'
    assert_equal post['cardPaymentMethodSpecificInput']['card']['cvv'], '123'
    assert_equal post['cardPaymentMethodSpecificInput']['card']['cardNumber'], '4567350000427977'
  end

  def test_add_payment_for_google_pay
    post = {}
    options = {}
    payment = @google_pay_network_token
    @gateway.send('add_payment', post, payment, options)
    assert_includes post.keys.first, 'mobilePaymentMethodSpecificInput'
    assert_equal post['mobilePaymentMethodSpecificInput']['paymentProductId'], '320'
    assert_equal post['mobilePaymentMethodSpecificInput']['authorizationMode'], 'FINAL_AUTHORIZATION'
    assert_equal post['mobilePaymentMethodSpecificInput']['encryptedPaymentData'], @google_pay_network_token.payment_data.to_s&.gsub('=>', ':')
  end

  def test_add_payment_for_apple_pay
    post = {}
    options = {}
    payment = @apple_pay_network_token
    @gateway.send('add_payment', post, payment, options)
    assert_includes post.keys, 'mobilePaymentMethodSpecificInput'
    assert_equal post['mobilePaymentMethodSpecificInput']['paymentProductId'], '302'
    assert_equal post['mobilePaymentMethodSpecificInput']['authorizationMode'], 'FINAL_AUTHORIZATION'
    assert_includes post['mobilePaymentMethodSpecificInput'].keys, 'decryptedPaymentData'
    assert_equal post['mobilePaymentMethodSpecificInput']['decryptedPaymentData']['dpan'], '4444333322221111'
    assert_equal post['mobilePaymentMethodSpecificInput']['decryptedPaymentData']['cryptogram'], 'EHuWW9PiBkWvqE5juRwDzAUFBAk='
    assert_equal post['mobilePaymentMethodSpecificInput']['decryptedPaymentData']['eci'], '05'
    assert_equal post['mobilePaymentMethodSpecificInput']['decryptedPaymentData']['expiryDate'], '1024'
  end

  def test_purchase_request_with_apple_pay
    stub_comms(@gateway, :ssl_request) do
      @gateway.purchase(@accepted_amount, @apple_pay_network_token)
    end.check_request(skip_response: true) do |_method, _endpoint, data, _headers|
      assert_equal '302', JSON.parse(data)['mobilePaymentMethodSpecificInput']['paymentProductId']
    end
  end

  # When requires_approval is false, a `purchase` makes one call (`auth`).
  def test_successful_purchase_with_requires_approval_false
    stub_comms(@gateway, :ssl_request) do
      @gateway.purchase(@accepted_amount, @credit_card, @options.merge(requires_approval: false))
    end.check_request do |_method, _endpoint, data, _headers|
      assert_equal false, JSON.parse(data)['cardPaymentMethodSpecificInput']['requiresApproval']
    end.respond_with(successful_authorize_response)
  end

  def test_successful_purchase_airline_fields
    options = @options.merge(
      airline_data: {
        code: 111,
        name: 'Spreedly Airlines',
        flight_date: '20190810',
        passenger_name: 'Randi Smith',
        agent_numeric_code: '12345',
        flight_legs: [
          { arrival_airport: 'BDL',
            origin_airport: 'RDU',
            date: '20190810',
            carrier_code: 'SA',
            number: 596,
            airline_class: 'ZZ' },
          { arrival_airport: 'RDU',
            origin_airport: 'BDL',
            date: '20190817',
            carrier_code: 'SA',
            number: 597,
            airline_class: 'ZZ' }
        ]
      }
    )
    stub_comms(@gateway, :ssl_request) do
      @gateway.purchase(@accepted_amount, @credit_card, options)
    end.check_request do |_method, _endpoint, data, _headers|
      assert_equal 111, JSON.parse(data)['order']['additionalInput']['airlineData']['code']
      assert_equal '20190810', JSON.parse(data)['order']['additionalInput']['airlineData']['flightDate']
      assert_equal 2, JSON.parse(data)['order']['additionalInput']['airlineData']['flightLegs'].length
    end.respond_with(successful_authorize_response, successful_capture_response)
  end

  def test_successful_purchase_lodging_fields
    options = @options.merge(
      lodging_data: {
        charges: [
          { charge_amount: '1000',
            charge_amount_currency_code: 'USD',
            charge_type: 'giftshop' }
        ],
        check_in_date: '20211223',
        check_out_date: '20211227',
        folio_number: 'randAssortmentofChars',
        is_confirmed_reservation: 'true',
        is_facility_fire_safety_conform: 'true',
        is_no_show: 'false',
        is_preference_smoking_room: 'false',
        number_of_adults: '2',
        number_of_nights: '1',
        number_of_rooms: '1',
        program_code: 'advancedDeposit',
        property_customer_service_phone_number: '5555555555',
        property_phone_number: '5555555555',
        renter_name: 'Guy',
        rooms: [
          { daily_room_rate: '25000',
            daily_room_rate_currency_code: 'USD',
            daily_room_tax_amount: '5',
            daily_room_tax_amount_currency_code: 'USD',
            number_of_nights_at_room_rate: '1',
            room_location: 'Courtyard',
            type_of_bed: 'Queen',
            type_of_room: 'Walled' }
        ]
      }
    )
    stub_comms(@gateway, :ssl_request) do
      @gateway.purchase(@accepted_amount, @credit_card, options)
    end.check_request do |_method, _endpoint, data, _headers|
      assert_equal 'advancedDeposit', JSON.parse(data)['order']['additionalInput']['lodgingData']['programCode']
      assert_equal '20211223', JSON.parse(data)['order']['additionalInput']['lodgingData']['checkInDate']
      assert_equal '1000', JSON.parse(data)['order']['additionalInput']['lodgingData']['charges'][0]['chargeAmount']
    end.respond_with(successful_authorize_response, successful_capture_response)
  end

  def test_successful_purchase_passenger_fields
    options = @options.merge(
      airline_data: {
        passengers: [
          { first_name: 'Randi',
            surname: 'Smith',
            surname_prefix: 'S',
            title: 'Mr' },
          { first_name: 'Julia',
            surname: 'Smith',
            surname_prefix: 'S',
            title: 'Mrs' }
        ]
      }
    )
    stub_comms(@gateway, :ssl_request) do
      @gateway.purchase(@accepted_amount, @credit_card, options)
    end.check_request do |_method, _endpoint, data, _headers|
      assert_equal 'Julia', JSON.parse(data)['order']['additionalInput']['airlineData']['passengers'][1]['firstName']
      assert_equal 2, JSON.parse(data)['order']['additionalInput']['airlineData']['passengers'].length
    end.respond_with(successful_authorize_response, successful_capture_response)
  end

  def test_purchase_passes_installments
    stub_comms(@gateway, :ssl_request) do
      @gateway.purchase(@accepted_amount, @credit_card, @options.merge(number_of_installments: '3'))
    end.check_request do |_method, _endpoint, data, _headers|
      assert_match(/"numberOfInstallments\":\"3\"/, data)
    end.respond_with(successful_authorize_response, successful_capture_response)
  end

  def test_purchase_does_not_run_capture_if_authorize_auto_captured
    response = stub_comms(@gateway, :ssl_request) do
      @gateway.purchase(@accepted_amount, @credit_card, @options)
    end.respond_with(successful_capture_response)

    assert_success response
    assert_equal 'CAPTURE_REQUESTED', response.params['payment']['status']
    assert_equal 1, response.responses.size
  end

  def test_authorize_with_pre_authorization_flag
    response = stub_comms(@gateway, :ssl_request) do
      @gateway.authorize(@accepted_amount, @credit_card, @options.merge(pre_authorization: true))
    end.check_request do |_method, _endpoint, data, _headers|
      assert_match(/PRE_AUTHORIZATION/, data)
    end.respond_with(successful_authorize_response_with_pre_authorization_flag)

    assert_success response
  end

  def test_authorize_without_pre_authorization_flag
    response = stub_comms(@gateway, :ssl_request) do
      @gateway.authorize(@accepted_amount, @credit_card, @options)
    end.check_request do |_method, _endpoint, data, _headers|
      assert_match(/FINAL_AUTHORIZATION/, data)
    end.respond_with(successful_authorize_response)

    assert_success response
  end

  def test_successful_authorization_with_extra_options
    options = @options.merge(
      {
        customer: '123987',
        email: 'example@example.com',
        order_id: '123',
        ip: '127.0.0.1',
        fraud_fields:
        {
          'website' => 'www.example.com',
          'giftMessage' => 'Happy Day!'
        },
        payment_product_id: '123ABC'
      }
    )

    response = stub_comms(@gateway, :ssl_request) do
      @gateway.authorize(@accepted_amount, @credit_card, options)
    end.check_request do |_method, _endpoint, data, _headers|
      assert_match %r("fraudFields":{"website":"www.example.com","giftMessage":"Happy Day!"}), data
      assert_match %r("merchantReference":"123"), data
      assert_match %r("customer":{"personalInformation":{"name":{"firstName":"Longbob","surname":"Longsen"}},"merchantCustomerId":"123987","contactDetails":{"emailAddress":"example@example.com","phoneNumber":"\(555\)555-5555"},"billingAddress":{"street":"My Street","houseNumber":"456","additionalInfo":"Apt 1","zip":"K1C2N6","city":"Ottawa","state":"ON","countryCode":"CA"}}}), data
      assert_match %r("paymentProductId":"123ABC"), data
    end.respond_with(successful_authorize_response)

    assert_success response
  end

  def test_successful_authorize_with_3ds_auth
    response = stub_comms(@gateway, :ssl_request) do
      @gateway.authorize(@accepted_amount, @credit_card, @options_3ds2)
    end.check_request do |_method, _endpoint, data, _headers|
      assert_match(/threeDSecure/, data)
      assert_match(/externalCardholderAuthenticationData/, data)
      assert_match(/"eci\":\"05\"/, data)
      assert_match(/"cavv\":\"jJ81HADVRtXfCBATEp01CJUAAAA=\"/, data)
      assert_match(/"xid\":\"BwABBJQ1AgAAAAAgJDUCAAAAAAA=\"/, data)
      assert_match(/"threeDSecureVersion\":\"2.1.0\"/, data)
      assert_match(/"directoryServerTransactionId\":\"97267598-FAE6-48F2-8083-C23433990FBC\"/, data)
      assert_match(/"acsTransactionId\":\"13c701a3-5a88-4c45-89e9-ef65e50a8bf9\"/, data)
      assert_match(/"cavvAlgorithm\":1/, data)
      assert_match(/"validationResult\":\"Y\"/, data)
    end.respond_with(successful_authorize_with_3ds2_data_response)

    assert_success response
  end

  def test_does_not_send_3ds_auth_when_empty
    response = stub_comms(@gateway, :ssl_request) do
      @gateway.authorize(@accepted_amount, @credit_card, @options)
    end.check_request do |_method, _endpoint, data, _headers|
      assert_not_match(/threeDSecure/, data)
      assert_not_match(/externalCardholderAuthenticationData/, data)
      assert_not_match(/cavv/, data)
      assert_not_match(/xid/, data)
      assert_not_match(/threeDSecureVersion/, data)
      assert_not_match(/directoryServerTransactionId/, data)
      assert_not_match(/acsTransactionId/, data)
      assert_not_match(/cavvAlgorithm/, data)
      assert_not_match(/validationResult/, data)
    end.respond_with(successful_authorize_response)

    assert_success response
  end

  def test_successful_authorize_with_3ds_exemption
    response = stub_comms(@gateway, :ssl_request) do
      @gateway.authorize(@accepted_amount, @credit_card, { three_ds_exemption_type: 'moto' })
    end.check_request do |_method, _endpoint, data, _headers|
      assert_match(/"transactionChannel\":\"MOTO\"/, data)
    end.respond_with(successful_authorize_with_3ds2_data_response)

    assert_success response
  end

  def test_truncates_first_name_to_15_chars
    credit_card = credit_card('4567350000427977', { first_name: 'thisisaverylongfirstname' })

    response = stub_comms(@gateway, :ssl_request) do
      @gateway.authorize(@accepted_amount, credit_card, @options)
    end.check_request do |_method, _endpoint, data, _headers|
      assert_match(/thisisaverylong/, data)
    end.respond_with(successful_authorize_response)

    assert_success response
    assert_equal '000000142800000000920000100001', response.authorization
  end

  def test_handles_blank_names
    credit_card = credit_card('4567350000427977', { first_name: nil, last_name: nil })

    response = stub_comms(@gateway, :ssl_request) do
      @gateway.authorize(@accepted_amount, credit_card, @options)
    end.respond_with(successful_authorize_response)

    assert_success response
  end

  def test_truncates_split_address_fields
    response = stub_comms(@gateway, :ssl_request) do
      @gateway.purchase(@accepted_amount, @credit_card, {
        billing_address: {
          address1: '1234 Supercalifragilisticexpialidociousthiscantbemorethanfiftycharacters',
          address2: 'Unit 6',
          city: '‎Portland',
          state: 'ME',
          zip: '09901',
          country: 'US'
        }
      })
    end.check_request do |_method, _endpoint, data, _headers|
      assert_equal(JSON.parse(data)['order']['customer']['billingAddress']['houseNumber'], '1234')
      assert_equal(JSON.parse(data)['order']['customer']['billingAddress']['street'], 'Supercalifragilisticexpialidociousthiscantbemoreth')
    end.respond_with(successful_capture_response)
    assert_success response
  end

  def test_failed_authorize
    response = stub_comms(@gateway, :ssl_request) do
      @gateway.authorize(@rejected_amount, @declined_card, @options)
    end.respond_with(failed_authorize_response)

    assert_failure response
    assert_equal 'Not authorised', response.message
  end

  def test_failed_capture
    response = stub_comms(@gateway, :ssl_request) do
      @gateway.capture(100, '', @options)
    end.respond_with(failed_capture_response)

    assert_failure response
  end

  def test_successful_inquire
    response = stub_comms(@gateway, :ssl_request) do
      @gateway.purchase(@accepted_amount, @credit_card, @options)
    end.respond_with(successful_capture_response)

    assert_success response

    response = stub_comms(@gateway, :ssl_request) do
      @gateway.inquire(response.authorization)
    end.respond_with(successful_inquire_response)

    assert_success response
  end

  def test_successful_void
    response = stub_comms(@gateway, :ssl_request) do
      @gateway.purchase(@accepted_amount, @credit_card, @options)
    end.respond_with(successful_capture_response)

    assert_success response

    void = stub_comms(@gateway, :ssl_request) do
      @gateway.void(response.authorization)
    end.respond_with(successful_void_response)

    assert_success void
  end

  def test_failed_void
    response = stub_comms(@gateway, :ssl_request) do
      @gateway.void('5d53a33d960c46d00f5dc061947d998c')
    end.check_request do |_method, endpoint, _data, _headers|
      assert_match(/5d53a33d960c46d00f5dc061947d998c/, endpoint)
    end.respond_with(failed_void_response)

    assert_failure response
  end

  def test_successful_provider_unresponsive_void
    response = stub_comms(@gateway, :ssl_request) do
      @gateway.void('5d53a33d960c46d00f5dc061947d998c')
    end.respond_with(successful_provider_unresponsive_void_response)

    assert_success response
  end

  def test_failed_provider_unresponsive_void
    response = stub_comms(@gateway, :ssl_request) do
      @gateway.void('5d53a33d960c46d00f5dc061947d998c')
    end.respond_with(failed_provider_unresponsive_void_response)

    assert_failure response
  end

  def test_successful_verify
    response = stub_comms(@gateway, :ssl_request) do
      @gateway.verify(@credit_card, @options)
    end.respond_with(successful_verify_response)
    assert_equal '000000219600000096240000100001', response.authorization

    assert_success response
  end

  def test_successful_verify_ogone_direct
    response = stub_comms(@gateway_direct, :ssl_request) do
      @gateway_direct.verify(@credit_card, @options)
    end.respond_with(successful_authorize_response, successful_void_response)
    assert_equal '000000142800000000920000100001', response.authorization

    assert_success response
  end

  def test_failed_verify_ogone_direct
    response = stub_comms(@gateway_direct, :ssl_request) do
      @gateway_direct.verify(@credit_card, @options)
    end.respond_with(failed_authorize_response)

    assert_failure response
  end

  def test_successful_refund
    response = stub_comms(@gateway, :ssl_request) do
      @gateway.authorize(@accepted_amount, @credit_card, @options)
    end.respond_with(successful_authorize_response)

    assert_equal '000000142800000000920000100001', response.authorization

    capture = stub_comms(@gateway, :ssl_request) do
      @gateway.capture(@accepted_amount, response.authorization)
    end.respond_with(successful_capture_response)

    refund = stub_comms(@gateway, :ssl_request) do
      @gateway.refund(@accepted_amount, capture.authorization)
    end.check_request do |_method, endpoint, _data, _headers|
      assert_match(/000000142800000000920000100001/, endpoint)
    end.respond_with(successful_refund_response)

    assert_success refund
  end

  def test_refund_passes_currency_code
    stub_comms(@gateway, :ssl_request) do
      @gateway.refund(@accepted_amount, '000000142800000000920000100001', { currency: 'COP' })
    end.check_request do |_method, _endpoint, data, _headers|
      assert_match(/"currencyCode\":\"COP\"/, data)
    end.respond_with(failed_refund_response)
  end

  def test_failed_refund
    response = stub_comms(@gateway, :ssl_request) do
      @gateway.refund(nil, '')
    end.respond_with(failed_refund_response)

    assert_failure response
  end

  def test_rejected_refund
    response = stub_comms(@gateway, :ssl_request) do
      @gateway.refund(@accepted_amount, '000000142800000000920000100001')
    end.respond_with(rejected_refund_response)

    assert_failure response
    assert_equal '1850', response.error_code
    assert_equal 'Status: REJECTED', response.message
  end

  def test_invalid_raw_response
    response = stub_comms(@gateway, :ssl_request) do
      @gateway.purchase(@accepted_amount, @credit_card, @options)
    end.respond_with(invalid_json_response)

    assert_failure response
    assert_match %r{^Invalid response received from the Ingenico ePayments}, response.message
  end

  def test_scrub
    assert @gateway.supports_scrubbing?
    assert_equal @gateway.scrub(pre_scrubbed), post_scrubbed
  end

  def test_scrub_invalid_response
    response = stub_comms(@gateway, :ssl_request) do
      @gateway.purchase(@accepted_amount, @credit_card, @options)
    end.respond_with(invalid_json_plus_card_data).message

    assert_equal @gateway.scrub(response), scrubbed_invalid_json_plus
  end

  def test_authorize_with_optional_idempotency_key_header
    response = stub_comms(@gateway, :ssl_request) do
      @gateway.authorize(@accepted_amount, @credit_card, @options.merge(idempotency_key: 'test123'))
    end.check_request do |_method, _endpoint, _data, headers|
      assert_equal headers['X-GCS-Idempotence-Key'], 'test123'
    end.respond_with(successful_authorize_response)

    assert_success response
  end

  private

  def pre_scrubbed
    %q(
    opening connection to api-sandbox.globalcollect.com:443...
    opened
    starting SSL for api-sandbox.globalcollect.com:443...
    SSL established
    <- "POST //v1/1428/payments HTTP/1.1\r\nContent-Type: application/json\r\nAuthorization: GCS v1HMAC:96f16a41890565d0:Bqv5QtSXi+SdqXUyoBBeXUDlRvi5DzSm49zWuJTLX9s=\r\nDate: Tue, 15 Mar 2016 14:32:13 GMT\r\nAccept-Encoding: gzip;q=1.0,deflate;q=0.6,identity;q=0.3\r\nAccept: */*\r\nUser-Agent: Ruby\r\nConnection: close\r\nHost: api-sandbox.globalcollect.com\r\nContent-Length: 560\r\n\r\n"
    <- "{\"order\":{\"amountOfMoney\":{\"amount\":\"100\",\"currencyCode\":\"USD\"},\"customer\":{\"merchantCustomerId\":null,\"personalInformation\":{\"name\":{\"firstName\":null,\"surname\":null}},\"billingAddress\":{\"street\":\"456 My Street\",\"additionalInfo\":\"Apt 1\",\"zip\":\"K1C2N6\",\"city\":\"Ottawa\",\"state\":\"ON\",\"countryCode\":\"CA\"}},\"contactDetails\":{\"emailAddress\":null}},\"cardPaymentMethodSpecificInput\":{\"paymentProductId\":\"1\",\"skipAuthentication\":\"true\",\"skipFraudService\":\"true\",\"card\":{\"cvv\":\"123\",\"cardNumber\":\"4567350000427977\",\"expiryDate\":\"0917\",\"cardholderName\":\"Longbob Longsen\"}}}"
    -> "HTTP/1.1 201 Created\r\n"
    -> "Date: Tue, 15 Mar 2016 18:32:14 GMT\r\n"
    -> "Server: Apache/2.4.16 (Unix) OpenSSL/1.0.1p\r\n"
    -> "Location: https://api-sandbox.globalcollect.com:443/v1/1428/payments/000000142800000000300000100001\r\n"
    -> "X-Powered-By: Servlet/3.0 JSP/2.2\r\n"
    -> "Connection: close\r\n"
    -> "Transfer-Encoding: chunked\r\n"
    -> "Content-Type: application/json\r\n"
    -> "\r\n"
    -> "457\r\n"
    reading 1111 bytes...
    -> "{\n   \"creationOutput\" : {\n      \"additionalReference\" : \"00000014280000000030\",\n      \"externalReference\" : \"000000142800000000300000100001\"\n   },\n   \"payment\" : {\n      \"id\" : \"000000142800000000300000100001\",\n      \"paymentOutput\" : {\n         \"amountOfMoney\" : {\n            \"amount\" : 100,\n            \"currencyCode\" : \"USD\"\n         },\n         \"references\" : {\n            \"paymentReference\" : \"0\"\n         },\n         \"paymentMethod\" : \"card\",\n         \"cardPaymentMethodSpecificOutput\" : {\n            \"paymentProductId\" : 1,\n            \"authorisationCode\" : \"OK1131\",\n            \"card\" : {\n               \"cardNumber\" : \"************7977\",\n               \"expiryDate\" : \"0917\"\n            },\n            \"fraudResults\" : {\n               \"fraudServiceResult\" : \"no-advice\",\n               \"avsResult\" : \"0\",\n               \"cvvResult\" : \"0\"\n            }\n         }\n      },\n      \"status\" : \"PENDING_APPROVAL\",\n      \"statusOutput\" : {\n         \"isCancellable\" : true,\n         \"statusCode\" : 600,\n         \"statusCodeChangeDateTime\" : \"20160315193214\",\n         \"isAuthorized\" : true\n      }\n   }\n}"
    read 1111 bytes
    reading 2 bytes...
    -> ""
    -> "\r\n"
    read 2 bytes
    -> "0\r\n"
    -> "\r\n"
    Conn close
    opening connection to api-sandbox.globalcollect.com:443...
    opened
    starting SSL for api-sandbox.globalcollect.com:443...
    SSL established
    <- "POST //v1/1428/payments/000000142800000000300000100001/approve HTTP/1.1\r\nContent-Type: application/json\r\nAuthorization: GCS v1HMAC:96f16a41890565d0:9GxB1mGvy8b2nXktFhxm9ppJVfcNrTNl7Szp/xiUXNc=\r\nDate: Tue, 15 Mar 2016 14:32:13 GMT\r\nAccept-Encoding: gzip;q=1.0,deflate;q=0.6,identity;q=0.3\r\nAccept: */*\r\nUser-Agent: Ruby\r\nConnection: close\r\nHost: api-sandbox.globalcollect.com\r\nContent-Length: 208\r\n\r\n"
    <- "{\"order\":{\"amountOfMoney\":{\"amount\":\"100\",\"currencyCode\":\"USD\"},\"customer\":{\"merchantCustomerId\":null,\"personalInformation\":{\"name\":{\"firstName\":null,\"surname\":null}}},\"contactDetails\":{\"emailAddress\":null}}}"
    -> "HTTP/1.1 200 OK\r\n"
    -> "Date: Tue, 15 Mar 2016 18:32:15 GMT\r\n"
    -> "Server: Apache/2.4.16 (Unix) OpenSSL/1.0.1p\r\n"
    -> "X-Powered-By: Servlet/3.0 JSP/2.2\r\n"
    -> "Connection: close\r\n"
    -> "Transfer-Encoding: chunked\r\n"
    -> "Content-Type: application/json\r\n"
    -> "\r\n"
    -> "3c7\r\n"
    reading 967 bytes...
    -> "{\n   \"payment\" : {\n      \"id\" : \"000000142800000000300000100001\",\n      \"paymentOutput\" : {\n         \"amountOfMoney\" : {\n            \"amount\" : 100,\n            \"currencyCode\" : \"USD\"\n         },\n         \"references\" : {\n            \"paymentReference\" : \"0\"\n         },\n         \"paymentMethod\" : \"card\",\n         \"cardPaymentMethodSpecificOutput\" : {\n            \"paymentProductId\" : 1,\n            \"authorisationCode\" : \"OK1131\",\n            \"card\" : {\n               \"cardNumber\" : \"************7977\",\n               \"expiryDate\" : \"0917\"\n            },\n            \"fraudResults\" : {\n               \"fraudServiceResult\" : \"no-advice\",\n               \"avsResult\" : \"0\",\n               \"cvvResult\" : \"0\"\n            }\n         }\n      },\n      \"status\" : \"CAPTURE_REQUESTED\",\n      \"statusOutput\" : {\n         \"isCancellable\" : true,\n         \"statusCode\" : 800,\n         \"statusCodeChangeDateTime\" : \"20160315193215\",\n         \"isAuthorized\" : true\n      }\n   }\n}"
    read 967 bytes
    reading 2 bytes...
    -> ""
    -> "\r\n"
    read 2 bytes
    -> "0\r\n"
    -> "\r\n"
    Conn close
    )
  end

  def post_scrubbed
    %q(
    opening connection to api-sandbox.globalcollect.com:443...
    opened
    starting SSL for api-sandbox.globalcollect.com:443...
    SSL established
    <- "POST //v1/1428/payments HTTP/1.1\r\nContent-Type: application/json\r\nAuthorization: [FILTERED]\r\nDate: Tue, 15 Mar 2016 14:32:13 GMT\r\nAccept-Encoding: gzip;q=1.0,deflate;q=0.6,identity;q=0.3\r\nAccept: */*\r\nUser-Agent: Ruby\r\nConnection: close\r\nHost: api-sandbox.globalcollect.com\r\nContent-Length: 560\r\n\r\n"
    <- "{\"order\":{\"amountOfMoney\":{\"amount\":\"100\",\"currencyCode\":\"USD\"},\"customer\":{\"merchantCustomerId\":null,\"personalInformation\":{\"name\":{\"firstName\":null,\"surname\":null}},\"billingAddress\":{\"street\":\"456 My Street\",\"additionalInfo\":\"Apt 1\",\"zip\":\"K1C2N6\",\"city\":\"Ottawa\",\"state\":\"ON\",\"countryCode\":\"CA\"}},\"contactDetails\":{\"emailAddress\":null}},\"cardPaymentMethodSpecificInput\":{\"paymentProductId\":\"1\",\"skipAuthentication\":\"true\",\"skipFraudService\":\"true\",\"card\":{\"cvv\":\"[FILTERED]\",\"cardNumber\":\"[FILTERED]\",\"expiryDate\":\"0917\",\"cardholderName\":\"Longbob Longsen\"}}}"
    -> "HTTP/1.1 201 Created\r\n"
    -> "Date: Tue, 15 Mar 2016 18:32:14 GMT\r\n"
    -> "Server: Apache/2.4.16 (Unix) OpenSSL/1.0.1p\r\n"
    -> "Location: https://api-sandbox.globalcollect.com:443/v1/1428/payments/000000142800000000300000100001\r\n"
    -> "X-Powered-By: Servlet/3.0 JSP/2.2\r\n"
    -> "Connection: close\r\n"
    -> "Transfer-Encoding: chunked\r\n"
    -> "Content-Type: application/json\r\n"
    -> "\r\n"
    -> "457\r\n"
    reading 1111 bytes...
    -> "{\n   \"creationOutput\" : {\n      \"additionalReference\" : \"00000014280000000030\",\n      \"externalReference\" : \"000000142800000000300000100001\"\n   },\n   \"payment\" : {\n      \"id\" : \"000000142800000000300000100001\",\n      \"paymentOutput\" : {\n         \"amountOfMoney\" : {\n            \"amount\" : 100,\n            \"currencyCode\" : \"USD\"\n         },\n         \"references\" : {\n            \"paymentReference\" : \"0\"\n         },\n         \"paymentMethod\" : \"card\",\n         \"cardPaymentMethodSpecificOutput\" : {\n            \"paymentProductId\" : 1,\n            \"authorisationCode\" : \"OK1131\",\n            \"card\" : {\n               \"cardNumber\" : \"************7977\",\n               \"expiryDate\" : \"0917\"\n            },\n            \"fraudResults\" : {\n               \"fraudServiceResult\" : \"no-advice\",\n               \"avsResult\" : \"0\",\n               \"cvvResult\" : \"0\"\n            }\n         }\n      },\n      \"status\" : \"PENDING_APPROVAL\",\n      \"statusOutput\" : {\n         \"isCancellable\" : true,\n         \"statusCode\" : 600,\n         \"statusCodeChangeDateTime\" : \"20160315193214\",\n         \"isAuthorized\" : true\n      }\n   }\n}"
    read 1111 bytes
    reading 2 bytes...
    -> ""
    -> "\r\n"
    read 2 bytes
    -> "0\r\n"
    -> "\r\n"
    Conn close
    opening connection to api-sandbox.globalcollect.com:443...
    opened
    starting SSL for api-sandbox.globalcollect.com:443...
    SSL established
    <- "POST //v1/1428/payments/000000142800000000300000100001/approve HTTP/1.1\r\nContent-Type: application/json\r\nAuthorization: [FILTERED]\r\nDate: Tue, 15 Mar 2016 14:32:13 GMT\r\nAccept-Encoding: gzip;q=1.0,deflate;q=0.6,identity;q=0.3\r\nAccept: */*\r\nUser-Agent: Ruby\r\nConnection: close\r\nHost: api-sandbox.globalcollect.com\r\nContent-Length: 208\r\n\r\n"
    <- "{\"order\":{\"amountOfMoney\":{\"amount\":\"100\",\"currencyCode\":\"USD\"},\"customer\":{\"merchantCustomerId\":null,\"personalInformation\":{\"name\":{\"firstName\":null,\"surname\":null}}},\"contactDetails\":{\"emailAddress\":null}}}"
    -> "HTTP/1.1 200 OK\r\n"
    -> "Date: Tue, 15 Mar 2016 18:32:15 GMT\r\n"
    -> "Server: Apache/2.4.16 (Unix) OpenSSL/1.0.1p\r\n"
    -> "X-Powered-By: Servlet/3.0 JSP/2.2\r\n"
    -> "Connection: close\r\n"
    -> "Transfer-Encoding: chunked\r\n"
    -> "Content-Type: application/json\r\n"
    -> "\r\n"
    -> "3c7\r\n"
    reading 967 bytes...
    -> "{\n   \"payment\" : {\n      \"id\" : \"000000142800000000300000100001\",\n      \"paymentOutput\" : {\n         \"amountOfMoney\" : {\n            \"amount\" : 100,\n            \"currencyCode\" : \"USD\"\n         },\n         \"references\" : {\n            \"paymentReference\" : \"0\"\n         },\n         \"paymentMethod\" : \"card\",\n         \"cardPaymentMethodSpecificOutput\" : {\n            \"paymentProductId\" : 1,\n            \"authorisationCode\" : \"OK1131\",\n            \"card\" : {\n               \"cardNumber\" : \"************7977\",\n               \"expiryDate\" : \"0917\"\n            },\n            \"fraudResults\" : {\n               \"fraudServiceResult\" : \"no-advice\",\n               \"avsResult\" : \"0\",\n               \"cvvResult\" : \"0\"\n            }\n         }\n      },\n      \"status\" : \"CAPTURE_REQUESTED\",\n      \"statusOutput\" : {\n         \"isCancellable\" : true,\n         \"statusCode\" : 800,\n         \"statusCodeChangeDateTime\" : \"20160315193215\",\n         \"isAuthorized\" : true\n      }\n   }\n}"
    read 967 bytes
    reading 2 bytes...
    -> ""
    -> "\r\n"
    read 2 bytes
    -> "0\r\n"
    -> "\r\n"
    Conn close
    )
  end

  def successful_authorize_response
    "{\n   \"creationOutput\" : {\n      \"additionalReference\" : \"00000014280000000092\",\n      \"externalReference\" : \"000000142800000000920000100001\"\n   },\n   \"payment\" : {\n      \"id\" : \"000000142800000000920000100001\",\n      \"paymentOutput\" : {\n         \"amountOfMoney\" : {\n            \"amount\" : 4005,\n            \"currencyCode\" : \"USD\"\n         },\n         \"references\" : {\n            \"paymentReference\" : \"0\"\n         },\n         \"paymentMethod\" : \"card\",\n         \"cardPaymentMethodSpecificOutput\" : {\n            \"paymentProductId\" : 1,\n            \"authorisationCode\" : \"OK1131\",\n            \"fraudResults\" : {\n               \"fraudServiceResult\" : \"no-advice\",\n               \"avsResult\" : \"0\",\n               \"cvvResult\" : \"0\"\n            },\n            \"card\" : {\n               \"cardNumber\" : \"************7977\",\n               \"expiryDate\" : \"0920\"\n            }\n         }\n      },\n      \"status\" : \"PENDING_APPROVAL\",\n      \"statusOutput\" : {\n         \"isCancellable\" : true,\n         \"statusCategory\" : \"PENDING_MERCHANT\",\n         \"statusCode\" : 600,\n         \"statusCodeChangeDateTime\" : \"20191203162910\",\n         \"isAuthorized\" : true,\n         \"isRefundable\" : false\n      }\n   }\n}"
  end

  def successful_verify_response
    "{\n   \"creationOutput\" : {\n      \"additionalReference\" : \"00000021960000009624\",\n      \"externalReference\" : \"000000219600000096240000100001\"\n   },\n   \"payment\" : {\n      \"id\" : \"000000219600000096240000100001\",\n      \"paymentOutput\" : {\n         \"amountOfMoney\" : {\n            \"amount\" : 0,\n            \"currencyCode\" : \"USD\"\n         },\n         \"references\" : {\n            \"paymentReference\" : \"0\"\n         },\n         \"paymentMethod\" : \"card\",\n         \"cardPaymentMethodSpecificOutput\" : {\n            \"paymentProductId\" : 1,\n            \"authorisationCode\" : \"OK1131\",\n            \"fraudResults\" : {\n               \"fraudServiceResult\" : \"no-advice\",\n               \"avsResult\" : \"0\",\n               \"cvvResult\" : \"0\"\n            },\n            \"card\" : {\n               \"cardNumber\" : \"************7977\",\n               \"cardholderName\" : \"Longbob Longsen\",\n               \"expiryDate\" : \"0925\"\n            }\n         }\n      },\n      \"status\" : \"ACCOUNT_VERIFIED\",\n      \"statusOutput\" : {\n         \"isCancellable\" : false,\n         \"isRetriable\" : false,\n         \"statusCategory\" : \"ACCOUNT_VERIFIED\",\n         \"statusCode\" : 300,\n         \"statusCodeChangeDateTime\" : \"20241010205138\",\n         \"isAuthorized\" : false,\n         \"isRefundable\" : false\n      }\n   }\n}"
  end

  def successful_authorize_with_3ds2_data_response
    %({\"creationOutput\":{\"additionalReference\":\"00000021960000002279\",\"externalReference\":\"000000219600000022790000100001\"},\"payment\":{\"id\":\"000000219600000022790000100001\",\"paymentOutput\":{\"amountOfMoney\":{\"amount\":100,\"currencyCode\":\"USD\"},\"references\":{\"paymentReference\":\"0\"},\"paymentMethod\":\"card\",\"cardPaymentMethodSpecificOutput\":{\"paymentProductId\":1,\"authorisationCode\":\"OK1131\",\"fraudResults\":{\"fraudServiceResult\":\"no-advice\",\"avsResult\":\"0\",\"cvvResult\":\"0\"},\"threeDSecureResults\":{\"cavv\":\"jJ81HADVRtXfCBATEp01CJUAAAA=\",\"directoryServerTransactionId\":\"97267598-FAE6-48F2-8083-C23433990FBC\",\"eci\":\"5\",\"threeDSecureVersion\":\"2.1.0\"},\"card\":{\"cardNumber\":\"************7977\",\"expiryDate\":\"0921\"}}},\"status\":\"PENDING_APPROVAL\",\"statusOutput\":{\"isCancellable\":true,\"statusCategory\":\"PENDING_MERCHANT\",\"statusCode\":600,\"statusCodeChangeDateTime\":\"20201029212921\",\"isAuthorized\":true,\"isRefundable\":false}}})
  end

  def failed_authorize_response
    %({\n   \"errorId\" : \"460ec7ed-f8be-4bd7-bf09-a4cbe07f774e\",\n   \"errors\" : [ {\n      \"code\" : \"430330\",\n      \"message\" : \"Not authorised\"\n   } ],\n   \"paymentResult\" : {\n      \"creationOutput\" : {\n         \"additionalReference\" : \"00000014280000000064\",\n         \"externalReference\" : \"000000142800000000640000100001\"\n      },\n      \"payment\" : {\n         \"id\" : \"000000142800000000640000100001\",\n         \"paymentOutput\" : {\n            \"amountOfMoney\" : {\n               \"amount\" : 100,\n               \"currencyCode\" : \"USD\"\n            },\n            \"references\" : {\n               \"paymentReference\" : \"0\"\n            },\n            \"paymentMethod\" : \"card\",\n            \"cardPaymentMethodSpecificOutput\" : {\n               \"paymentProductId\" : 1\n            }\n         },\n         \"status\" : \"REJECTED\",\n         \"statusOutput\" : {\n            \"errors\" : [ {\n               \"code\" : \"430330\",\n               \"requestId\" : \"55635\",\n               \"message\" : \"Not authorised\"\n            } ],\n            \"isCancellable\" : false,\n            \"statusCode\" : 100,\n            \"statusCodeChangeDateTime\" : \"20160316154235\",\n            \"isAuthorized\" : false\n         }\n      }\n   }\n})
  end

  def successful_authorize_response_with_pre_authorization_flag
    %({\n   \"creationOutput\" : {\n      \"additionalReference\" : \"00000021960000000968\",\n      \"externalReference\" : \"000000219600000009680000100001\"\n   },\n   \"payment\" : {\n      \"id\" : \"000000219600000009680000100001\",\n      \"paymentOutput\" : {\n         \"amountOfMoney\" : {\n            \"amount\" : 4005,\n            \"currencyCode\" : \"USD\"\n         },\n         \"references\" : {\n            \"paymentReference\" : \"0\"\n         },\n         \"paymentMethod\" : \"card\",\n         \"cardPaymentMethodSpecificOutput\" : {\n            \"paymentProductId\" : 1,\n            \"authorisationCode\" : \"OK1131\",\n            \"fraudResults\" : {\n               \"fraudServiceResult\" : \"no-advice\",\n               \"avsResult\" : \"0\",\n               \"cvvResult\" : \"0\"\n            },\n            \"card\" : {\n               \"cardNumber\" : \"************7977\",\n               \"expiryDate\" : \"0920\"\n            }\n         }\n      },\n      \"status\" : \"PENDING_APPROVAL\",\n      \"statusOutput\" : {\n         \"isCancellable\" : true,\n         \"statusCategory\" : \"PENDING_MERCHANT\",\n         \"statusCode\" : 600,\n         \"statusCodeChangeDateTime\" : \"20191017153833\",\n         \"isAuthorized\" : true,\n         \"isRefundable\" : false\n      }\n   }\n})
  end

  def successful_capture_response
    "{\n   \"payment\" : {\n      \"id\" : \"000000142800000000920000100001\",\n      \"paymentOutput\" : {\n         \"amountOfMoney\" : {\n            \"amount\" : 4005,\n            \"currencyCode\" : \"USD\"\n         },\n         \"references\" : {\n            \"paymentReference\" : \"0\"\n         },\n         \"paymentMethod\" : \"card\",\n         \"cardPaymentMethodSpecificOutput\" : {\n            \"paymentProductId\" : 1,\n            \"authorisationCode\" : \"OK1131\",\n            \"fraudResults\" : {\n               \"fraudServiceResult\" : \"no-advice\",\n               \"avsResult\" : \"0\",\n               \"cvvResult\" : \"0\"\n            },\n            \"card\" : {\n               \"cardNumber\" : \"************7977\",\n               \"expiryDate\" : \"0920\"\n            }\n         }\n      },\n      \"status\" : \"CAPTURE_REQUESTED\",\n      \"statusOutput\" : {\n         \"isCancellable\" : true,\n         \"statusCategory\" : \"PENDING_CONNECT_OR_3RD_PARTY\",\n         \"statusCode\" : 800,\n         \"statusCodeChangeDateTime\" : \"20191203163030\",\n         \"isAuthorized\" : true,\n         \"isRefundable\" : false\n      }\n   }\n}"
  end

  def failed_capture_response
    %({\n   \"errorId\" : \"6a3ffb94-e1ed-41bc-b9fb-4a8759b3fed7\",\n   \"errors\" : [ {\n      \"code\" : \"1002\",\n      \"propertyName\" : \"paymentId\",\n      \"message\" : \"INVALID_PAYMENT_ID\"\n   } ]\n})
  end

  def successful_refund_response
    %({\n   \"id\" : \"000000142800000000920000100001\",\n   \"refundOutput\" : {\n      \"amountOfMoney\" : {\n         \"amount\" : 4005,\n         \"currencyCode\" : \"USD\"\n      },\n      \"references\" : {\n         \"paymentReference\" : \"0\"\n      },\n      \"paymentMethod\" : \"card\",\n      \"cardRefundMethodSpecificOutput\" : {\n      }\n   },\n   \"status\" : \"REFUND_REQUESTED\",\n   \"statusOutput\" : {\n      \"isCancellable\" : true,\n      \"statusCode\" : 800,\n      \"statusCodeChangeDateTime\" : \"20160317215704\"\n   }\n})
  end

  def failed_refund_response
    %({\n   \"errorId\" : \"1bd31e6a-39dd-4214-941a-088a320e0286\",\n   \"errors\" : [ {\n      \"code\" : \"1002\",\n      \"propertyName\" : \"paymentId\",\n      \"message\" : \"INVALID_PAYMENT_ID\"\n   } ]\n})
  end

  def rejected_refund_response
    %({\n   \"id\" : \"00000022184000047564000-100001\",\n   \"refundOutput\" : {\n      \"amountOfMoney\" : {\n         \"amount\" : 627000,\n         \"currencyCode\" : \"COP\"\n      },\n      \"references\" : {\n         \"merchantReference\" : \"17091GTgZmcC\",\n         \"paymentReference\" : \"0\"\n      },\n      \"paymentMethod\" : \"card\",\n      \"cardRefundMethodSpecificOutput\" : {\n      }\n   },\n   \"status\" : \"REJECTED\",\n   \"statusOutput\" : {\n      \"isCancellable\" : false,\n      \"statusCategory\" : \"UNSUCCESSFUL\",\n      \"statusCode\" : 1850,\n      \"statusCodeChangeDateTime\" : \"20170313230631\"\n   }\n})
  end

  def successful_inquire_response
    %({\n   \"payment\" : {\n      \"id\" : \"000001263340000255950000100001\",\n      \"paymentOutput\" : {\n         \"amountOfMoney\" : {\n            \"amount\" : 126000,\n            \"currencyCode\" : \"ARS\"\n         },\n         \"references\" : {\n            \"merchantReference\" : \"10032994586\",\n            \"paymentReference\" : \"0\",\n            \"providerId\" : \"88\"\n         },\n         \"paymentMethod\" : \"card\",\n         \"cardPaymentMethodSpecificOutput\" : {\n            \"paymentProductId\" : 1,\n            \"authorisationCode\" : \"002792\",\n            \"fraudResults\" : {\n               \"fraudServiceResult\" : \"no-advice\",\n               \"avsResult\" : \"0\",\n               \"cvvResult\" : \"0\"\n            },\n            \"card\" : {\n               \"cardNumber\" : \"493768******8095\",\n               \"expiryDate\" : \"0824\"\n            }\n         }\n      },\n      \"status\" : \"PENDING_APPROVAL\",\n      \"statusOutput\" : {\n         \"isCancellable\" : true,\n         \"statusCode\" : 600,\n         \"statusCodeChangeDateTime\" : \"20220214193408\",\n         \"isAuthorized\" : true\n        }\n   }\n  })
  end

  def successful_void_response
    %({\n   \"payment\" : {\n      \"id\" : \"000001263340000255950000100001\",\n      \"paymentOutput\" : {\n         \"amountOfMoney\" : {\n            \"amount\" : 126000,\n            \"currencyCode\" : \"ARS\"\n         },\n         \"references\" : {\n            \"merchantReference\" : \"10032994586\",\n            \"paymentReference\" : \"0\",\n            \"providerId\" : \"88\"\n         },\n         \"paymentMethod\" : \"card\",\n         \"cardPaymentMethodSpecificOutput\" : {\n            \"paymentProductId\" : 1,\n            \"authorisationCode\" : \"002792\",\n            \"fraudResults\" : {\n               \"fraudServiceResult\" : \"no-advice\",\n               \"avsResult\" : \"0\",\n               \"cvvResult\" : \"0\"\n            },\n            \"card\" : {\n               \"cardNumber\" : \"493768******8095\",\n               \"expiryDate\" : \"0824\"\n            }\n         }\n      },\n      \"status\" : \"CANCELLED\",\n      \"statusOutput\" : {\n         \"isCancellable\" : false,\n         \"statusCategory\" : \"UNSUCCESSFUL\",\n         \"statusCode\" : 99999,\n         \"statusCodeChangeDateTime\" : \"20220214193408\",\n         \"isAuthorized\" : false,\n         \"isRefundable\" : false\n      }\n   },\n   \"cardPaymentMethodSpecificOutput\" : {\n      \"voidResponseId\" : \"00\"\n   }\n})
  end

  def failed_void_response
    %({\n   \"errorId\" : \"9e38736e-15f3-4d6b-8517-aad3029619b9\",\n   \"errors\" : [ {\n      \"code\" : \"1002\",\n      \"propertyName\" : \"paymentId\",\n      \"message\" : \"INVALID_PAYMENT_ID\"\n   } ]\n})
  end

  def successful_provider_unresponsive_void_response
    %({\n   \"payment\" : {\n      \"id\" : \"000001263340000255950000100001\",\n      \"paymentOutput\" : {\n         \"amountOfMoney\" : {\n            \"amount\" : 126000,\n            \"currencyCode\" : \"ARS\"\n         },\n         \"references\" : {\n            \"merchantReference\" : \"10032994586\",\n            \"paymentReference\" : \"0\",\n            \"providerId\" : \"88\"\n         },\n         \"paymentMethod\" : \"card\",\n         \"cardPaymentMethodSpecificOutput\" : {\n            \"paymentProductId\" : 1,\n            \"authorisationCode\" : \"002792\",\n            \"fraudResults\" : {\n               \"fraudServiceResult\" : \"no-advice\",\n               \"avsResult\" : \"0\",\n               \"cvvResult\" : \"0\"\n            },\n            \"card\" : {\n               \"cardNumber\" : \"493768******8095\",\n               \"expiryDate\" : \"0824\"\n            }\n         }\n      },\n      \"status\" : \"CANCELLED\",\n      \"statusOutput\" : {\n         \"isCancellable\" : false,\n         \"statusCategory\" : \"UNSUCCESSFUL\",\n         \"statusCode\" : 99999,\n         \"statusCodeChangeDateTime\" : \"20220214193408\",\n         \"isAuthorized\" : false,\n         \"isRefundable\" : false\n      }\n   },\n   \"cardPaymentMethodSpecificOutput\" : {\n      \"voidResponseId\" : \"98\"\n   }\n})
  end

  def failed_provider_unresponsive_void_response
    %({\n   \"payment\" : {\n      \"id\" : \"000000142800000000920000100001\",\n      \"paymentOutput\" : {\n         \"amountOfMoney\" : {\n            \"amount\" : 100,\n            \"currencyCode\" : \"ARS\"\n         },\n         \"references\" : {\n            \"merchantReference\" : \"0\",\n            \"paymentReference\" : \"0\",\n            \"providerId\" : \"88\"\n         },\n         \"paymentMethod\" : \"card\",\n         \"cardPaymentMethodSpecificOutput\" : {\n            \"paymentProductId\" : 3,\n            \"authorisationCode\" : \"123456\",\n            \"fraudResults\" : {\n               \"fraudServiceResult\" : \"no-advice\",\n               \"avsResult\" : \"0\",\n               \"cvvResult\" : \"0\"\n            },\n            \"card\" : {\n               \"cardNumber\" : \"************7977\",\n               \"expiryDate\" : \"0125\"\n            }\n         }\n      },\n      \"status\" : \"REJECTED\",\n      \"statusOutput\" : {\n         \"isCancellable\" : false,\n         \"statusCategory\" : \"UNSUCCESSFUL\",\n         \"statusCode\" : 99999,\n         \"statusCodeChangeDateTime\" : \"20191011201122\",\n         \"isAuthorized\" : false,\n         \"isRefundable\" : false\n      }\n   },\n   \"cardPaymentMethodSpecificOutput\" : {\n      \"voidResponseId\" : \"98\"\n   }\n})
  end

  def invalid_json_response
    '<!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML 2.0//EN">
      <html><head>
        <title>502 Proxy Error</title>
      </head><body>
        <h1>Proxy Error</h1>
        <p>The proxy server received an invalid
            response from an upstream server.<br />
            The proxy server could not handle the request <em><a href="/v1/9040/payments">POST&nbsp;/v1/9040/payments</a></em>.<p>
            Reason: <strong>Error reading from remote server</strong></p></p>
      </body></html>'
  end

  def invalid_json_plus_card_data
    %q(<!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML 2.0//EN">
      <html><head>
      <title>502 Proxy Error</title>
      </head></html>
      opening connection to api-sandbox.globalcollect.com:443...
      opened
      starting SSL for api-sandbox.globalcollect.com:443...
      SSL established
      <- "POST //v1/1428/payments HTTP/1.1\r\nContent-Type: application/json\r\nAuthorization: GCS v1HMAC:96f16a41890565d0:Bqv5QtSXi+SdqXUyoBBeXUDlRvi5DzSm49zWuJTLX9s=\r\nDate: Tue, 15 Mar 2016 14:32:13 GMT\r\nAccept-Encoding: gzip;q=1.0,deflate;q=0.6,identity;q=0.3\r\nAccept: */*\r\nUser-Agent: Ruby\r\nConnection: close\r\nHost: api-sandbox.globalcollect.com\r\nContent-Length: 560\r\n\r\n"
      <- "{\"order\":{\"amountOfMoney\":{\"amount\":\"100\",\"currencyCode\":\"USD\"},\"customer\":{\"merchantCustomerId\":null,\"personalInformation\":{\"name\":{\"firstName\":null,\"surname\":null}},\"billingAddress\":{\"street\":\"456 My Street\",\"additionalInfo\":\"Apt 1\",\"zip\":\"K1C2N6\",\"city\":\"Ottawa\",\"state\":\"ON\",\"countryCode\":\"CA\"}},\"contactDetails\":{\"emailAddress\":null}},\"cardPaymentMethodSpecificInput\":{\"paymentProductId\":\"1\",\"skipAuthentication\":\"true\",\"skipFraudService\":\"true\",\"card\":{\"cvv\":\"123\",\"cardNumber\":\"4567350000427977\",\"expiryDate\":\"0917\",\"cardholderName\":\"Longbob Longsen\"}}}"
      -> "HTTP/1.1 201 Created\r\n"
      -> "Date: Tue, 15 Mar 2016 18:32:14 GMT\r\n"
      -> "Server: Apache/2.4.16 (Unix) OpenSSL/1.0.1p\r\n"
      -> "Location: https://api-sandbox.globalcollect.com:443/v1/1428/payments/000000142800000000300000100001\r\n"
      -> "X-Powered-By: Servlet/3.0 JSP/2.2\r\n"
      -> "Connection: close\r\n"
      -> "Transfer-Encoding: chunked\r\n"
      -> "Content-Type: application/json\r\n"
      -> "\r\n"
      -> "457\r\n")
  end

  def scrubbed_invalid_json_plus
    'Invalid response received from the Ingenico ePayments (formerly GlobalCollect) API.  Please contact Ingenico ePayments if you continue to receive this message.  (The raw response returned by the API was "<!DOCTYPE HTML PUBLIC \\"-//IETF//DTD HTML 2.0//EN\\">\\n      <html><head>\\n      <title>502 Proxy Error</title>\\n      </head></html>\\n      opening connection to api-sandbox.globalcollect.com:443...\\n      opened\\n      starting SSL for api-sandbox.globalcollect.com:443...\\n      SSL established\\n      <- \\"POST //v1/1428/payments HTTP/1.1\\\\r\\\\nContent-Type: application/json\\\\r\\\\nAuthorization: [FILTERED]\\\\r\\\\nDate: Tue, 15 Mar 2016 14:32:13 GMT\\\\r\\\\nAccept-Encoding: gzip;q=1.0,deflate;q=0.6,identity;q=0.3\\\\r\\\\nAccept: */*\\\\r\\\\nUser-Agent: Ruby\\\\r\\\\nConnection: close\\\\r\\\\nHost: api-sandbox.globalcollect.com\\\\r\\\\nContent-Length: 560\\\\r\\\\n\\\\r\\\\n\\"\\n      <- \\"{\\\\\\"order\\\\\\":{\\\\\\"amountOfMoney\\\\\\":{\\\\\\"amount\\\\\\":\\\\\\"100\\\\\\",\\\\\\"currencyCode\\\\\\":\\\\\\"USD\\\\\\"},\\\\\\"customer\\\\\\":{\\\\\\"merchantCustomerId\\\\\\":null,\\\\\\"personalInformation\\\\\\":{\\\\\\"name\\\\\\":{\\\\\\"firstName\\\\\\":null,\\\\\\"surname\\\\\\":null}},\\\\\\"billingAddress\\\\\\":{\\\\\\"street\\\\\\":\\\\\\"456 My Street\\\\\\",\\\\\\"additionalInfo\\\\\\":\\\\\\"Apt 1\\\\\\",\\\\\\"zip\\\\\\":\\\\\\"K1C2N6\\\\\\",\\\\\\"city\\\\\\":\\\\\\"Ottawa\\\\\\",\\\\\\"state\\\\\\":\\\\\\"ON\\\\\\",\\\\\\"countryCode\\\\\\":\\\\\\"CA\\\\\\"}},\\\\\\"contactDetails\\\\\\":{\\\\\\"emailAddress\\\\\\":null}},\\\\\\"cardPaymentMethodSpecificInput\\\\\\":{\\\\\\"paymentProductId\\\\\\":\\\\\\"1\\\\\\",\\\\\\"skipAuthentication\\\\\\":\\\\\\"true\\\\\\",\\\\\\"skipFraudService\\\\\\":\\\\\\"true\\\\\\",\\\\\\"card\\\\\\":{\\\\\\"cvv\\\\\\":\\\\\\"[FILTERED]\\\\\\",\\\\\\"cardNumber\\\\\\":\\\\\\"[FILTERED]\\\\\\",\\\\\\"expiryDate\\\\\\":\\\\\\"0917\\\\\\",\\\\\\"cardholderName\\\\\\":\\\\\\"Longbob Longsen\\\\\\"}}}\\"\\n      -> \\"HTTP/1.1 201 Created\\\\r\\\\n\\"\\n      -> \\"Date: Tue, 15 Mar 2016 18:32:14 GMT\\\\r\\\\n\\"\\n      -> \\"Server: Apache/2.4.16 (Unix) OpenSSL/1.0.1p\\\\r\\\\n\\"\\n      -> \\"Location: https://api-sandbox.globalcollect.com:443/v1/1428/payments/000000142800000000300000100001\\\\r\\\\n\\"\\n      -> \\"X-Powered-By: Servlet/3.0 JSP/2.2\\\\r\\\\n\\"\\n      -> \\"Connection: close\\\\r\\\\n\\"\\n      -> \\"Transfer-Encoding: chunked\\\\r\\\\n\\"\\n      -> \\"Content-Type: application/json\\\\r\\\\n\\"\\n      -> \\"\\\\r\\\\n\\"\\n      -> \\"457\\\\r\\\\n\\"")'
  end
end
