require 'erb'
require 'uri'
require 'net/http'
require 'net/https'
require 'json'
require_relative 'simple_rest_client/version'

# Base class to help easily create REST HTTP clients.
#
# Example client:
#   class ExampleAPI < SimpleRESTClient
#     def initialize
#       super(address: 'api.example.com')
#     end
#     def resource_list filter
#       get('/resource_list', query: {filter: filter}).body
#     end
#   end
# Alternatively, you can do it without making a child class:
#   require 'simple_rest_client'
#
#   class ExampleAPI
#     def initialize
#       @simple_rest_client = SimpleRESTClient.new(address: 'api.example.com')
#     end
#     def resource_list filter
#       @simple_rest_client.get('/resource_list', query: {filter: filter}).body
#     end
#   end
# You can define your own methods, regarding your own problem domain, to ease access to any resource in your API. Make use of any of the HTTP verb methods provided to easily interface with your API.
class SimpleRESTClient

  # Default value for #net_http_attrs.
  DEFAULT_NET_HTTP_ATTRS = {
    open_timeout: 5,
    read_timeout: 30,
    ssl_timeout:  10,
  }.freeze

  # Default value for #default_expected_status_code
  DEFAULT_EXPECTED_STATUS_CODE           = Hash.new(:successful)
  DEFAULT_EXPECTED_STATUS_CODE[:get]     = 200
  DEFAULT_EXPECTED_STATUS_CODE[:head]    = 200
  DEFAULT_EXPECTED_STATUS_CODE[:post]    = [200, 201, 202, 204, 205]
  DEFAULT_EXPECTED_STATUS_CODE[:put]     = [200, 201, 202, 204, 205]
  DEFAULT_EXPECTED_STATUS_CODE[:delete]  = [200, 202]
  DEFAULT_EXPECTED_STATUS_CODE[:options] = [200, 204]
  DEFAULT_EXPECTED_STATUS_CODE[:trace]   = 200
  DEFAULT_EXPECTED_STATUS_CODE[:patch]   = [200, 201, 202, 204, 205]
  DEFAULT_EXPECTED_STATUS_CODE.freeze

  # Hostname or IP address of the server.
  attr_reader :address

  # Port of the server. Defaults to 80 if HTTP and 443 if HTTPS (depends on <tt>net_http_attrs[:use_ssl] == true</tt>).
  attr_reader :port

  # Base path to prefix all requests with. Must be URL encoded when needed.
  attr_reader :base_path

  # Base query string to use in all requests. Must be provided as a Hash.
  attr_reader :base_query

  # Base headers to be used in all requests. Must be provided as a Hash.
  attr_reader :base_headers

  # Hash with default attributes for Net::HTTP. Defaults to DEFAULT_NET_HTTP_ATTRS. If #port is 443 and :use_ssl is not specified, it will be set to true.
  attr_reader :net_http_attrs

  # Username for basic auth.
  attr_reader :username

  # Password for basic auth.
  attr_reader :password
  # Hash with default values for #request. Keys are Symbols to HTTP methods (eg: <tt>:get</tt>), values are anything accepted by #request's expected_status_code parameter.
  # General purpose defaults are defined at DEFAULT_EXPECTED_STATUS_CODE.
  attr_reader :default_expected_status_code

  # List of hooks that are called before each request
  attr_reader :pre_request_hooks

  # List of hooks that are called after each request.
  attr_reader :post_request_hooks

  # List of hooks that are called around each request.
  attr_reader :around_request_hook

  # Logger instance where to log to.
  attr_reader :logger

  # :section:

  # Creates a new HTTP client. Please refer to each attribute's documentation for details and default values.
  def initialize(
    address:                      ,
    port:                         nil,
    base_path:                    nil,
    base_query:                   {},
    base_headers:                 {},
    net_http_attrs:               DEFAULT_NET_HTTP_ATTRS.dup,
    username:                     nil,
    password:                     nil,
    default_expected_status_code: DEFAULT_EXPECTED_STATUS_CODE.dup,
    logger:                       nil
  )
    @address                        = address
    @port                           = if port
                                        port
                                      else
                                        net_http_attrs[:use_ssl] ? 443 : 80
                                      end
    @base_path                      = base_path
    @base_query                     = base_query
    @base_headers                   = base_headers
    @net_http_attrs                 = net_http_attrs
    unless @net_http_attrs.has_key?(:use_ssl)
      @net_http_attrs[:use_ssl] = true if port == 443
    end
    @username                       = username
    @password                       = password
    @default_expected_status_code   = default_expected_status_code
    @logger                         = logger
    @net_http                       = nil
    @pre_request_hooks              = []
    @post_request_hooks             = []
    @around_request_hooks           = []
    @around_request                 = proc { |block, request| block.call }
    setup_logging
    yield self if block_given?
  end


  # Instance of Net::HTTP.
  def net_http
    return @net_http if @net_http
    @net_http = Net::HTTP.new(address, port)
    @net_http_attrs.each { |key, value| @net_http.send(:"#{key}=", value) }
    ObjectSpace.define_finalizer( self, proc { @net_http.finish } )
    @net_http
  end

  # :section: Hooks

  # Register given block at #pre_request_hooks.
  def add_pre_request_hook &block # :yields: request
    raise ArgumentError, "A block must be provided!" unless block
    @pre_request_hooks << block
  end

  # Register given block at #post_request_hooks.
  def add_post_request_hook &block # :yields: response, request
    raise ArgumentError, "A block must be provided!" unless block
    @post_request_hooks << block
  end

  # Register given block at #around_request_hook. Given block must call received block argument, to make the request. Exemple:
  #  simple_rest_client.add_around_request_hook do |block, request|
  #    # do something before the request is made
  #    response = block.call
  #    # do something after the request was made
  #  end
  def add_around_request_hook &new_block # :yields: block, request
    raise ArgumentError, "A block must be provided!" unless new_block
    old_around_block = @around_request
    @around_request = proc do |block, request|
      old_around_block.call(
        proc{new_block.call(block, request)},
        request
      )
    end
  end

  # :section: Generic requests

  # Performs a generic HTTP method request.
  # http_method:: HTTP method to invoke.
  # path:: URI path.
  # query:: URI query, in form of a Hash.
  # headers:: Request headers in form of a Hash. Must not conflict with #base_headers.
  # body / body_stream:: For requests tha supporting sending a body, use one of the two to define a payload.
  # expected_status_code:: Validate response's HTTP status-code. Can be given as a code number (<tt>200</tt>), Array of codes (<tt>[200, 201]</tt>), Range (<tt>(200..202)</tt>), one of <tt>:informational</tt>, <tt>:successful</tt>, <tt>:redirection</tt>, <tt>:client_error</tt>, <tt>:server_error</tt> or response class (Net::HTTPSuccess). To disable status code validation, set to <tt>nil</tt>.
  # net_http_attrs: Hash with attributes of #net_http to change only for this request. Useful for setting up Net::HTTP#read_timeout only for slow requests.
  # :call-seq:
  # request(http_method, path, query: {}, headers: {}, body: nil, body_stream: nil, expected_status_code: :successful) {|http_response| ... } -> (block return value)
  # request(http_method, path, query: {}, headers: {}, body: nil, body_stream: nil, expected_status_code: :successful) -> Net::HTTPResponse
  def request(
    http_method,
    path,
    query: {},
    headers: {},
    body: nil,
    body_stream: nil,
    expected_status_code: default_expected_status_code[http_method],
    net_http_attrs: {},
    &block
  )
    uri = build_uri(path, query)
    request = build_request(http_method, uri, headers, body, body_stream)
    with_net_http_attrs(net_http_attrs) do
      @around_request.call(
        proc do
          do_request(request, expected_status_code, &block)
        end,
        request
      )
    end
  end

  # Define a instance method for given HTTP request method.
  def self.http_method http_method # :nodoc:
    self.class_eval do
      define_method(http_method) do |*args, &block|
        request(http_method, *args, &block)
      end
    end
  end

  # :section: HTTP Methods

  # RFC7231 Hypertext Transfer Protocol (HTTP/1.1): Semantics and Content

  ##
  # :method: get
  # Perform a GET request.
  # It is a wrapper around #request method, and accepts the same arguments.
  # :call-seq: get(*request_args, &block)
  http_method :get

  ##
  # Perform a HEAD request.
  # It is a wrapper around #request method, and accepts the same arguments.
  # :method: head
  # :call-seq: head(*request_args, &block)
  http_method :head

  ##
  # Perform a POST request.
  # It is a wrapper around #request method, and accepts the same arguments.
  # :method: post
  # :call-seq: post(*request_args, &block)
  http_method :post

  ##
  # Perform a PUT request.
  # It is a wrapper around #request method, and accepts the same arguments.
  # :method: put
  # :call-seq: put(*request_args, &block)
  http_method :put

  ##
  # Perform a DELETE request.
  # It is a wrapper around #request method, and accepts the same arguments.
  # :method: delete
  # :call-seq: delete(*request_args, &block)
  http_method :delete

  ##
  # Perform a OPTIONS request.
  # It is a wrapper around #request method, and accepts the same arguments.
  # :method: options
  # :call-seq: options(*request_args, &block)
  http_method :options

  ##
  # Perform a TRACE request.
  # It is a wrapper around #request method, and accepts the same arguments.
  # :method: trace
  # :call-seq: trace(*request_args, &block)
  http_method :trace

  # RFC5789 PATCH Method for HTTP

  ##
  # Perform a PATCH request.
  # It is a wrapper around #request method, and accepts the same arguments.
  # :call-seq: patch(*request_args, &block)
  # :method: patch
  http_method :patch

  # :section:

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

  private

  def build_uri path='/', query={}
    # Base
    build_args = {
      host: address,
      port: port,
      path: "#{base_path}/#{path}".gsub(/\/+/, '/'),
    }
    # Basic Auth
    build_args.merge!(
      userinfo: "#{ERB::Util.url_encode(username)}:#{ERB::Util.url_encode(password.to_s)}",
    ) if username
    # Query
    conflicting_query_keys = (base_query.keys & query.keys)
    unless conflicting_query_keys.empty?
      raise ArgumentError, "Passed query parameters conflict with base_query parameters: #{conflicting_query_keys.join(', ')}."
    end
    merged_query = base_query.merge(query)
    build_args.merge!(
      query: URI.encode_www_form(merged_query),
    ) unless merged_query.empty?
    # Build
    ( net_http_attrs[:use_ssl] ? URI::HTTPS : URI::HTTP ).build(build_args)
  end

  def build_request http_method, uri, headers, body, body_stream
    begin
      request_class = Net::HTTP.const_get(http_method.downcase.capitalize)
    rescue NameError
      raise ArgumentError, "Unknown HTTP method named #{http_method}!"
    end
    if !request_class.const_get(:REQUEST_HAS_BODY) && body
      raise ArgumentError.new("unknown keyword: body")
    end
    if !request_class.const_get(:REQUEST_HAS_BODY) && body_stream
      raise ArgumentError.new("unknown keyword: body_stream")
    end
    request = request_class.new(
      uri,
      build_headers(headers)
    )
    request.basic_auth(username, password.to_s) if username
    request.body = body if body
    request.body_stream = body_stream if body_stream
    request
  end

  def build_headers headers
    conflicting_header_keys = base_headers.keys & headers.keys
    unless conflicting_header_keys.empty?
      raise ArgumentError, "Passed headers conflict with base_headers: #{conflicting_header_keys.join(', ')}."
    end
    base_headers
      .merge(headers)
      .merge('user-agent' => "#{SimpleRESTClient}/#{SimpleRESTClient::VERSION} (#{RUBY_DESCRIPTION}) Ruby")
      .map{|k,v| [k.to_s, v.to_s]}
      .to_h
  end

  # Set given #net_http attributes, execute given block, and restore all attributes.
  def with_net_http_attrs net_http_attrs
    # Save original #net_http attributes
    original_net_http_attrs = {}
    net_http_attrs.each_key do |attribute|
      original_net_http_attrs[attribute] = net_http.send(attribute)
    end
    begin
      # Set temporary #net_http attributes
      net_http_attrs.each_key do |attribute|
        net_http.send(:"#{attribute}=", net_http_attrs[attribute])
      end
      # Run block
      yield
    ensure
      # Restore original #net_http attributes
      net_http_attrs.each_key do |attribute|
        net_http.send(:"#{attribute}=", original_net_http_attrs[attribute])
      end
    end
  end

  def do_request(request, expected_status_code, &block)
    @pre_request_hooks.each do |pre_request_hook|
      pre_request_hook.call(request)
    end
    net_http.request(request) do |response|
      validate_status_code(response, expected_status_code)
      fix_response_encoding(response)
      @post_request_hooks.each do |post_request_hook|
        post_request_hook.call(response, request)
      end
      if block
        return block.call(response)
      else
        return response
      end
    end
  end

  def validate_status_code response, expected_status_code
    return unless expected_status_code
    if Class === expected_status_code
      unless expected_status_code === response
        raise UnexpectedStatusCode.new(expected_status_code, response)
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
    unless expected_status_code_list.include?(Integer(response.code))
      raise UnexpectedStatusCode.new(expected_status_code, response)
    end
  end

  # Implement a solution for https://bugs.ruby-lang.org/issues/2567
  def fix_response_encoding response
    fix_response_body(response)
    fix_response_read_body(response)
  end

  # Wrap around Net:HTTPResponse#body to make it respect headers charset.
  def fix_response_body response
    original_body = response.method(:body)
    response.define_singleton_method(:body) do |*args, &block|
      body = original_body.call(*args, &block)
      if response.type_params['charset'] && body.respond_to?(:force_encoding) &&
        body.force_encoding(response.type_params['charset'])
      end
      body
    end
  end

  # Wrap around Net:HTTPResponse#read_body to make it respect headers charset.
  def fix_response_read_body(response)
    original_read_body = response.method(:read_body)
    response.define_singleton_method(:read_body) do |dest=nil, &block|
      charset = type_params['charset']
      charset = 'ASCII-8BIT' unless charset
      if block
        final_block = proc do |chunk|
          if charset
            block.call(chunk.force_encoding(charset))
          else
            block.call(chunk)
          end
        end
        original_read_body.call(dest, &final_block)
      else
        ret_value = original_read_body.call(dest)
        if charset
          dest.force_encoding(charset) if dest
          ret_value.force_encoding(charset)
        end
        ret_value
      end
    end
  end

  def log level, message
    return unless logger
    logger.send(level, message)
  end

  def setup_logging
    return unless logger
    add_pre_request_hook do |request|
      log(:info, "#{request.method.upcase} #{request.uri}")
    end
    add_around_request_hook do |block, request|
      begin
        block.call
      rescue
        log(:error, "Failed to #{request.method.upcase} #{request.uri}: #{$!}")
        raise $!
      end
    end
  end

end
