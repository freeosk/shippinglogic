module Shippinglogic
  class UPS
    # An interface to the track services provided by UPS. Allows you to get an array of events for a specific
    # tracking number.
    #
    # == Accessor methods / options
    #
    # * <tt>tracking_number</tt> - the tracking number
    #
    # === Simple Example
    #
    # Here is a very simple example:
    #
    #   ups = Shippinglogic::UPS.new(key, password, account)
    #   tracking_details = ups.track(:tracking_number => "my number")
    #
    #   tracking_details.status
    #   # => "Delivered"
    #
    #   tracking_details.signature_name
    #   # => "KKING"
    #
    #   tracking_details.events.first
    #   # => #<Shippinglogic::UPS::Track::Event @postal_code="95817", @name="Delivered", @state="CA",
    #   #     @city="Sacramento", @type="Delivered", @country="US", @occured_at=Mon Dec 08 10:43:37 -0500 2008>
    #
    #   tracking_details.events.first.name
    #   # => "Delivered"
    #
    # === Note
    #
    # UPS does support locating packages through means other than a tracking number.
    # These are not supported and probably won't be until someone needs them. It should
    # be fairly simple to add, but I could not think of a reason why anyone would want to track
    # a package with anything other than a tracking number.
    #
    # duplicated_waybill is a placeholder because UPS does not support error
    class Track < Service
      def self.path
        "/Track"
      end

      class Details
        # Each tracking result is an object of this class
        class Event; attr_accessor :name, :type, :occured_at, :city, :state, :postal_code, :country; end

        attr_accessor :origin_city, :origin_state, :origin_country,
          :destination_city, :destination_state, :destination_country, :destination_zip,
          :signature_name, :service_type, :status, :delivery_at, :estimated_delivery_at,
          :events, :ship_date, :duplicated_waybill

        def initialize(response)
          details = response.fetch(:shipment, {})

          if origin = details.fetch(:shipper, {})[:address]
            self.origin_city    = origin[:city]
            self.origin_state   = origin[:state_province_code]
            self.origin_country = origin[:country_code]
          end

          if destination = details.fetch(:ship_to, {})[:address]
            self.destination_city     = destination[:city]
            self.destination_state    = destination[:state_province_code]
            self.destination_zip      = destination[:postal_code]
            self.destination_country  = destination[:country_code]
          end

          package            = details[:package]
          events             = details[:activity].is_a?(Array) ? details[:activity] : [details[:activitiy]].compact
          last_event         = events.first
          delivery           = details.fetch(:delivery_details, {})[:delivery_date]
          estimated_delivery = details.fetch(:estimated_delivery_details, {})
          pickup_date        = details[:pickup_date]

          self.signature_name        = last_event && last_event[:signed_for_by_name]
          self.service_type          = details[:service][:description]
          self.status                = details.fetch(:current_status, {})[:description]
          self.ship_date             = pickup_date && Time.parse(pickup_date)
          self.estimated_delivery_at = estimated_delivery && Time.parse(estimated_delivery[:date] + estimated_delivery[:time])
          self.delivery_at           = delivery && Time.parse(delivery[:date] + delivery[:time])

          #I don't need events right now
          #TODO: modify this to comply with new format
          #self.events = events.collect do |details|
          #  event             = Event.new
          #  status            = details[:status][:status_type]
          #  event.name        = status[:description]
          #  event.type        = status[:code]
          #  #FIXME The proper spelling is "occurred", not "occured."
          #  event.occured_at  = Time.parse(details[:date] + details[:time])
          #  location          = details[:activity_location][:address]
          #  event.city        = location[:city]
          #  event.state       = location[:state_province_code]
          #  event.postal_code = location[:postal_code]
          #  event.country     = location[:country_code]
          #  event
          #end
        end
      end

      attribute :tracking_number, :string

      private

      # The parent class Service requires that we define this method. This is our kicker. This method is only
      # called when we need to deal with information from UPS. Notice the caching into the @target variable.
      def target
        @target ||= Details.new(request(build_request))
      end

      # Just building some XML to send off to UPS. UPS requires this particualar format.
      def build_request
        b = builder
        build_authentication(b)
        b.instruct!

        b.TrackRequest do
          b.Request do
            b.RequestAction "Track"
            b.RequestOption "activity"
          end

          b.IncludeFreight "01"
          b.TrackingNumber tracking_number
        end
      end
    end
  end
end
