require 'erb'
require 'uri'
require 'net/http'
require 'net/https'
require_relative 'simple_rest_client/response'
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

  # Around request hook.
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
    default_expected_status_code: SimpleRESTClient::Response::DEFAULT_EXPECTED_STATUS_CODE.dup,
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
    @around_request_hook            = proc { |block, request| block.call }
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
    old_around_block = @around_request_hook
    @around_request_hook = proc do |block, request|
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
  # expected_status_code:: Status-code validation. See SimpleRESTClient::Response#expected_status_code.
  # \net_http_attrs:: Hash with attributes of #net_http to change only for this request. Useful for setting up Net::HTTP#read_timeout only for slow requests.
  # receive_format:: Set format of response (eg: <tt>:json</tt>). This will set <tt>Accept</tt> header on the requset, and will set <tt>:receive_format</tt> on SimpleRESTClient::Response, to allow usage of SimpleRESTClient::Response#parsed_body.
  # To use Net::HTTPResponse#read_body, you must pass a block (otherwise, response body will be cached to memory).
  # :call-seq:
  # request(http_method, path, query: {}, headers: {}, body: nil, body_stream: nil, expected_status_code: default_expected_status_code[http_method], receive_format: nil) {|simple_rest_client_response| ... } -> (block return value)
  # request(http_method, path, query: {}, headers: {}, body: nil, body_stream: nil, expected_status_code: default_expected_status_code[http_method], receive_format: nil) -> SimpleRESTClient::Response
  def request(
    http_method,
    path,
    query: {},
    headers: {},
    body: nil,
    body_stream: nil,
    expected_status_code: default_expected_status_code[http_method],
    receive_format: nil,
    net_http_attrs: {},
    &block
  )
    uri = build_uri(path, query)
    request = build_request(http_method, uri, headers, body, body_stream, receive_format)
    with_net_http_attrs(net_http_attrs) do
      @around_request_hook.call(
        proc do
          do_request(request, expected_status_code, receive_format, &block)
        end,
        request
      )
    end
  end

  # :section: HTTP Methods

  # Define a instance method for given HTTP request method.
  def self.http_method http_method # :nodoc:
    self.class_eval do
      define_method(http_method) do |path, *request_opts, &block|
        request(http_method, path, *request_opts, &block)
      end
    end
  end

  # RFC7231 Hypertext Transfer Protocol (HTTP/1.1): Semantics and Content

  ##
  # :method: get
  # Perform a GET request.
  # It is a wrapper around #request method, and accepts the same arguments.
  # :call-seq:
  # get(path, *request_opts) {|simple_rest_client_response| ... } -> (block return value)
  # get(path, *request_opts) -> SimpleRESTClient::Response
  http_method :get

  ##
  # Perform a HEAD request.
  # It is a wrapper around #request method, and accepts the same arguments.
  # :method: head
  # :call-seq:
  # head(path, *request_opts) {|simple_rest_client_response| ... } -> (block return value)
  # head(path, *request_opts) -> SimpleRESTClient::Response
  http_method :head

  ##
  # Perform a POST request.
  # It is a wrapper around #request method, and accepts the same arguments.
  # :method: post
  # :call-seq:
  # post(path, *request_opts) {|simple_rest_client_response| ... } -> (block return value)
  # post(path, *request_opts) -> SimpleRESTClient::Response
  http_method :post

  ##
  # Perform a PUT request.
  # It is a wrapper around #request method, and accepts the same arguments.
  # :method: put
  # :call-seq:
  # put(path, *request_opts) {|simple_rest_client_response| ... } -> (block return value)
  # put(path, *request_opts) -> SimpleRESTClient::Response
  http_method :put

  ##
  # Perform a DELETE request.
  # It is a wrapper around #request method, and accepts the same arguments.
  # :method: delete
  # :call-seq:
  # delete(path, *request_opts) {|simple_rest_client_response| ... } -> (block return value)
  # delete(path, *request_opts) -> SimpleRESTClient::Response
  http_method :delete

  ##
  # Perform a OPTIONS request.
  # It is a wrapper around #request method, and accepts the same arguments.
  # :method: options
  # :call-seq:
  # options(path, *request_opts) {|simple_rest_client_response| ... } -> (block return value)
  # options(path, *request_opts) -> SimpleRESTClient::Response
  http_method :options

  ##
  # Perform a TRACE request.
  # It is a wrapper around #request method, and accepts the same arguments.
  # :method: trace
  # :call-seq:
  # trace(path, *request_opts) {|simple_rest_client_response| ... } -> (block return value)
  # trace(path, *request_opts) -> SimpleRESTClient::Response
  http_method :trace

  # RFC5789 PATCH Method for HTTP

  ##
  # Perform a PATCH request.
  # It is a wrapper around #request method, and accepts the same arguments.
  # :call-seq:
  # patch(path, *request_opts) {|simple_rest_client_response| ... } -> (block return value)
  # patch(path, *request_opts) -> SimpleRESTClient::Response
  # :method: patch
  http_method :patch

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

  def build_request http_method, uri, headers, body, body_stream, receive_format
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
      build_headers(headers, receive_format)
    )
    request.basic_auth(username, password.to_s) if username
    request.body = body if body
    request.body_stream = body_stream if body_stream
    request
  end

  def build_headers headers, receive_format
    conflicting_header_keys = base_headers.keys & headers.keys
    unless conflicting_header_keys.empty?
      raise ArgumentError, "Passed headers conflict with base_headers: #{conflicting_header_keys.join(', ')}."
    end
    final_headers = base_headers
      .dup
      .merge(headers)
      .merge('user-agent' => "#{SimpleRESTClient}/#{SimpleRESTClient::VERSION} (#{RUBY_DESCRIPTION}) Ruby")
    set_accept_header(final_headers, receive_format)
    final_headers
      .map{|k,v| [k.to_s, v.to_s]}
      .to_h
  end

  def set_accept_header headers, receive_format
    return unless receive_format
    headers['Accept'] = case receive_format
      when :json
        'application/json'
      when :yaml
        'text/yaml'
      else
        raise ArgumentError, "Unknown receive_format: #{receive_format.inspect}"
      end
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

  def do_request(request, expected_status_code, receive_format, &block)
    @pre_request_hooks.each do |pre_request_hook|
      pre_request_hook.call(request)
    end
    if block
      net_http.request(request) do |net_httpresponse|
        return block.call(
          process_response(
            request,
            net_httpresponse,
            expected_status_code,
            receive_format
          )
        )
      end
    else
      process_response(
        request,
        net_http.request(request),
        expected_status_code,
        receive_format
      )
    end
  end

  def process_response(
    request,
    net_httpresponse,
    expected_status_code,
    receive_format
  )
    fix_response_encoding(net_httpresponse)
    response = Response.new(
      net_httpresponse: net_httpresponse,
      expected_status_code: expected_status_code,
      receive_format: receive_format
    )
    response.validate_status_code
    @post_request_hooks.each do |post_request_hook|
      post_request_hook.call(response, request)
    end
    response
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
        if ret_value && charset
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
