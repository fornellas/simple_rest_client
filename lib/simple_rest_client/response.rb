require 'delegate'

class SimpleRESTClient

  # Wrapper for Net::HTTPResponse, with some extra methods. This class uses SimpleDelegator to delegate all methods to a Net::HTTPResponse object.
  class Response < SimpleDelegator

    # Raised when an unexpected HTTP status code was returned.
    class UnexpectedStatusCode < RuntimeError
      attr_reader :response, :expected_status_code
      def initialize expected_status_code, response
        @expected_status_code = expected_status_code
        @response             = response
      end
      def to_s
        "Expected HTTP status code to be #{expected_status_code.inspect}, but got #{response.code}."
      end
    end

    # Raised when an unexpected content type was returned.
    class UnexpectedContentType < RuntimeError
      attr_reader :response, :expected_content_type
      def initialize expected_content_type, response
        @expected_content_type = expected_content_type
        @response             = response
      end
      def to_s
        "Expected content type to be #{expected_content_type.inspect}, but got #{response['content-type'].inspect}."
      end
    end

    # Default value for #default_expected_status_code
    DEFAULT_EXPECTED_STATUS_CODE           = Hash.new(:successful)
    DEFAULT_EXPECTED_STATUS_CODE[:get]     = 200
    DEFAULT_EXPECTED_STATUS_CODE[:head]    = 200
    DEFAULT_EXPECTED_STATUS_CODE[:post]    = [200, 201, 202, 204, 205]
    DEFAULT_EXPECTED_STATUS_CODE[:put]     = [200, 201, 202, 204, 205]
    DEFAULT_EXPECTED_STATUS_CODE[:delete]  = [200, 202, 204]
    DEFAULT_EXPECTED_STATUS_CODE[:options] = [200, 204]
    DEFAULT_EXPECTED_STATUS_CODE[:trace]   = 200
    DEFAULT_EXPECTED_STATUS_CODE[:patch]   = [200, 201, 202, 204, 205]
    DEFAULT_EXPECTED_STATUS_CODE.freeze

    # Instance of Net::HTTPResponse
    attr_reader :net_httpresponse

    # Validation rule for #net_httpresponse status-code. Can be given as a code number (<tt>200</tt>), Array of codes (<tt>[200, 201]</tt>), Range (<tt>(200..202)</tt>), one of <tt>:informational</tt>, <tt>:successful</tt>, <tt>:redirection</tt>, <tt>:client_error</tt>, <tt>:server_error</tt> or response class (Net::HTTPSuccess). To disable status code validation, set to <tt>nil</tt>. Set to nil to disale validation.
    attr_reader :expected_status_code

    # Format of response, used by #parsed_body. Supported formats: <tt>:json</tt>.
    attr_reader :receive_format

    def initialize(
      net_httpresponse:,
      expected_status_code: nil,
      receive_format: nil
    )
      @net_httpresponse     = net_httpresponse
      @expected_status_code = expected_status_code
      @receive_format       = receive_format
      super(net_httpresponse)
    end

    # Validate response's status code against #expected_status_code, and raises an exception if response's status-code is unexpected.
    # If #expected_status_code is nil, this method does nothnig.
    def validate_status_code
      return unless expected_status_code
      if Class === expected_status_code
        unless expected_status_code === net_httpresponse
          raise UnexpectedStatusCode.new(expected_status_code, net_httpresponse)
        else
          return
        end
      end
      expected_status_code_list = case expected_status_code
        when Integer          ; [expected_status_code]
        when Array, Range     ; expected_status_code
        when Symbol
          case expected_status_code
          when :informational ; (100...200)
          when :successful    ; (200...300)
          when :redirection   ; (300...400)
          when :client_error  ; (400...500)
          when :server_error  ; (500...600)
          else
            raise ArgumentError.new("Invalid expected_status_code symbol: #{expected_status_code.inspect}.")
          end
        else
          raise ArgumentError, "Invalid expected_status_code argument: #{expected_status_code.inspect}."
        end
      unless expected_status_code_list.include?(Integer(net_httpresponse.code))
        raise UnexpectedStatusCode.new(expected_status_code, net_httpresponse)
      end
    end

    # Returns a parsed object following #receive_format.
    def parsed_body
      raise RuntimeError, "\#receive_format unset!" unless receive_format
      parse_metohd = :"parse_#{receive_format}"
      if self.respond_to?(parse_metohd)
        send(parse_metohd)
      else
        raise ArgumentError, "Don't know how to parse receive_format: #{receive_format.inspect}!"
      end
    end

    private

    def parse_json
      require 'json'
      expected_content_type = 'application/json'
      unless content_type == expected_content_type
        raise UnexpectedContentType.new(net_httpresponse, expected_content_type)
      end
      JSON.parse(body)
    end

  end
end
